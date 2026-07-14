#!/usr/bin/env bash
# Lint + simulate a decomposable FU (all modes run in one sim; mode is runtime).
# Usage: ./run.sh [module_basename]   (default: fu_add_sub_decomp)
#   RTL = rtl/<module>.sv, TB = tb/tb_<module>.sv, top = tb_<module>
#   Optional DPI-C golden tb/<module>_golden.c is compiled in with -mf16c when present.
set -euo pipefail
cd "$(dirname "$0")"

command -v verilator >/dev/null 2>&1 || module load verilator/5.044 2>/dev/null || true

MOD="${1:-fu_add_sub_decomp}"
RTL="rtl/${MOD}.sv"
TB="tb/tb_${MOD}.sv"
GOLDEN="tb/${MOD}_golden.c"
mkdir -p build

echo "== lint (-Wall) : ${MOD} =="
verilator --lint-only -Wall "$RTL"

# Optional DPI-C golden (e.g. hardware-FP reference).
EXTRA=()
if [ -f "$GOLDEN" ]; then
  echo "== dpi golden : ${GOLDEN} =="
  EXTRA+=(-CFLAGS "-mf16c" "$GOLDEN")
fi

echo "== build + sim : ${MOD} =="
verilator --binary --timing \
  -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module "tb_${MOD}" \
  --Mdir build/obj_dir \
  "$RTL" "$TB" ${EXTRA[@]+"${EXTRA[@]}"}

"build/obj_dir/Vtb_${MOD}" | tee build/sim.log
grep -q '^PASS:' build/sim.log && echo "run.sh: OK" || { echo "run.sh: FAIL"; exit 1; }
