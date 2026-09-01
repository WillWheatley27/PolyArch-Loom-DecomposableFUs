#!/usr/bin/env bash
# Lint + simulate decomposable FUs (all modes run in one sim; mode is runtime).
# Usage: ./run.sh [module_basename|all]   (default: fu_add_sub_decomp)
#   Legacy tests: TB = tb/tb_<module>.sv, top = tb_<module>
#   Shared-core tests: TB = rtl/tb_<module>.sv, top = tb
#   Standalone baselines: ./run.sh standalone (fu_add_sub_32x2/16x4/8x8)
#   Optional DPI-C golden tb/<module>_golden.c is compiled in with -mf16c when present.
set -euo pipefail
cd "$(dirname "$0")"

command -v verilator >/dev/null 2>&1 || module load verilator/5.044 2>/dev/null || true
if ! command -v verilator >/dev/null 2>&1; then
  echo "run.sh: verilator not found (expected module verilator/5.044)" >&2
  exit 127
fi

# The site compiler wrapper defaults its cache temp directory to /run/user, which may
# be read-only in batch/sandbox jobs. Caching is optional and should not gate verification.
export CCACHE_DISABLE=1

mkdir -p build

SHARED_MODULES=(
  fu_add_sub_gen
  fu_mult_decomp
  fu_min_max_gen
  fu_rounding_gen
  fu_fp_cmp_gen
  fu_fp_min_max_gen
  fu_abs_gen
  fu_barrel_shift_gen
  fu_cmp_gen
)

STANDALONE_MODULES=(
  fu_add_sub_32x2
  fu_add_sub_16x4
  fu_add_sub_8x8
)

run_one() {
  local mod="$1"
  local rtl="rtl/${mod}.sv"
  local tb top golden core_top obj_dir log binary
  local -a dw_args=()
  local -a extra=()

  if [[ ! -f "$rtl" && -f "rtl/standalone/${mod}.sv" ]]; then
    rtl="rtl/standalone/${mod}.sv"
  fi
  if [[ ! -f "$rtl" ]]; then
    echo "run.sh: missing RTL: $rtl" >&2
    return 2
  fi

  if [[ -f "tb/tb_${mod}.sv" ]]; then
    tb="tb/tb_${mod}.sv"
    top="tb_${mod}"
  elif [[ -f "rtl/tb_${mod}.sv" ]]; then
    tb="rtl/tb_${mod}.sv"
    top="tb"
  elif [[ -f "rtl/standalone/tb_${mod}.sv" ]]; then
    tb="rtl/standalone/tb_${mod}.sv"
    top="tb_${mod}"
  else
    echo "run.sh: missing testbench for $mod" >&2
    return 2
  fi

  golden="tb/${mod}_golden.c"
  core_top="$(sed -nE 's/^module[[:space:]]+([A-Za-z_][A-Za-z0-9_$]*).*/\1/p' "$rtl" | sed -n '1p')"
  if [[ -z "$core_top" ]]; then
    echo "run.sh: could not find a top-level module in $rtl" >&2
    return 2
  fi

  # Resolve DesignWare simulation models only for RTL that instantiates a DW cell.
  if rg -q '\b(DW_[A-Za-z0-9_]+|DW01_[A-Za-z0-9_]+)\b' "$rtl"; then
    local syn_dw="${SYN_DW:-/mnt/nas0/software/synopsys/syn/Y-2026.03-SP1/dw/sim_ver}"
    echo "== designware : $syn_dw =="
    dw_args+=(-y "$syn_dw" +libext+.v tb/dw_waivers.vlt)
  fi

  echo "== lint (-Wall) : $mod ($core_top) =="
  # Generator-family files intentionally contain a core and several capability wrappers,
  # so the filename need not equal the core module name.
  verilator --lint-only -Wall -Wno-DECLFILENAME --top-module "$core_top" \
    "${dw_args[@]}" "$rtl"

  if [[ -f "$golden" ]]; then
    echo "== dpi golden : $golden =="
    extra+=(-CFLAGS "-mf16c" "$golden")
  fi

  obj_dir="build/obj_${mod}"
  log="build/${mod}.log"
  binary="${obj_dir}/V${top}"
  echo "== build + sim : $mod =="
  verilator --binary --timing \
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
    --top-module "$top" \
    --Mdir "$obj_dir" \
    "${dw_args[@]}" \
    "$rtl" "$tb" "${extra[@]}"

  "$binary" | tee "$log"
  if ! rg -q '^PASS([:[:space:]])' "$log"; then
    echo "run.sh: FAIL ($mod)" >&2
    return 1
  fi
  echo "run.sh: OK ($mod)"
}

target="${1:-fu_add_sub_decomp}"
if [[ "$target" == "all" ]]; then
  for module in "${SHARED_MODULES[@]}"; do
    run_one "$module"
  done
  echo "run.sh: ALL SHARED CORES OK (${#SHARED_MODULES[@]} families)"
elif [[ "$target" == "standalone" ]]; then
  for module in "${STANDALONE_MODULES[@]}"; do
    run_one "$module"
  done
  echo "run.sh: ALL ADD/SUB STANDALONES OK (${#STANDALONE_MODULES[@]} modules)"
else
  run_one "$target"
fi
