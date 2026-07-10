#!/usr/bin/env bash
# Lint + simulate fu_add_sub_decomp (all modes run in one sim; mode is runtime).
set -euo pipefail
cd "$(dirname "$0")"

command -v verilator >/dev/null 2>&1 || module load verilator/5.044 2>/dev/null || true

RTL=rtl/fu_add_sub_decomp.sv
TB=tb/tb_fu_add_sub_decomp.sv
mkdir -p build

echo "== lint (-Wall) =="
verilator --lint-only -Wall "$RTL"

echo "== build + sim =="
verilator --binary --timing \
  -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module tb_fu_add_sub_decomp \
  --Mdir build/obj_dir \
  "$RTL" "$TB"

build/obj_dir/Vtb_fu_add_sub_decomp | tee build/sim.log
grep -q '^PASS:' build/sim.log && echo "run.sh: OK" || { echo "run.sh: FAIL"; exit 1; }
