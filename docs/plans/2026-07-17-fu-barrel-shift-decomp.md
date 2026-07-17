# fu_barrel_shift_decomp — Implementation Plan

**Date:** 2026-07-17
**Spec:** `docs/specs/2026-07-17-fu-barrel-shift-decomp-design.md`

TDD, native-SV golden (shift is exact).

## Step 1 — RED: testbench + stub
- `tb/tb_fu_barrel_shift_decomp.sv`: golden shifts each lane (`SLL/SRL/SRA`) at lane width with
  the low-`log2(w)`-bit amount; per mode; repack. Directed (each type × width; amounts 0/1/w-1/≥w;
  SRA sign-fill; cross-lane isolation) + ~20k random over `(mode, shift_op, a, b)`. Reuse
  handshake tasks.
- `rtl/fu_barrel_shift_decomp.sv` **stub**: handshake; `out_data = in_data_0 & in_data_1`
  (not a shift) → RED.
- Verify: `./run.sh fu_barrel_shift_decomp` → lint clean, sim FAIL.

## Step 2 — GREEN
- Three shift helpers `sh16/sh32/sh64(shift_op, x, amt)` (SLL/SRL/SRA via `<<`/`>>`/`$signed>>>`).
- Per-mode results p1/p2/p4 from lane slices + per-lane amounts; mode mux.
- Waive UNUSEDSIGNAL on `in_data_1` (shift-count masking) and clk/rst_n.
- Verify: `PASS:`; other modules still pass.

## Step 3 — docs / build
- README section; commit series (docs → RED → GREEN → README), author `WillWheatley27`,
  subject-only; push.
