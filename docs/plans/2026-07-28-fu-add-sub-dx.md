# fu_add_sub_dx — Implementation Plan

**Spec:** `docs/specs/2026-07-28-fu-add-sub-dx-design.md`

TDD, same gate as the rest of the repo: `verilator --lint-only -Wall` clean **and** testbench
`PASS:`. New wrinkle: DesignWare. `run.sh` auto-detects a `DW_*` instantiation and adds the Synopsys
`sim_ver` library (`-y … +libext+.v`) plus `tb/dw_waivers.vlt` (scopes `-Wall` to our RTL).

## Steps

1. **Spec** (done) — `docs/specs/2026-07-28-fu-add-sub-dx-design.md`.
2. **RED** — `tb/tb_fu_add_sub_dx.sv` (native-SV golden, 1×64 + 2×32, per-lane `op_sel`, directed
   mode-isolation + handshake + 20k random) against a **stub** RTL (`out_data = a & b`, no DW). Expect
   lint clean, sim FAIL.
3. **GREEN** — replace stub with `DW_addsub_dx #(.width(64), .p1_width(32))` instantiation +
   invert-b/carry-in per-lane subtract logic. Expect lint clean, `PASS:`.
4. **README** — add an `fu_add_sub_dx` section (64/32 family, DW-based).
5. **Commit series** (WillWheatley27, subject-only, no AI traces): docs → RED → GREEN → README.
6. **Synthesize** SAED14nm, both corners, with `synthetic_library = dw_foundation.sldb` so DC maps
   the DW duplex block. Record area/speed corners + a note that it's the DW `_dx` duplex.
7. **Chart** — append `add_sub_dx` as a new bottom row (per chart-ordering preference).

## Risks / checks

- **Verilator + DW model** — validated in a probe: Verilator compiles through `// synopsys
  translate_off` and the `DW_addsub_dx` model simulates correctly (1×W, 2-seg, per-segment ci).
- **1×64 subtract** across bit 32 — directed test asserts carry crosses in 1×64 and is blocked in
  2×32 (the mode-isolation proof).
- **Synth DW mapping** — add `$DC_HOME/libraries/syn` to `search_path` and `dw_foundation.sldb` to
  `synthetic_library`/`link_library`.
