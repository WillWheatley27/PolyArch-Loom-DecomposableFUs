# AddSub Window-Fix Experiment: Three Rewrites Aimed at the 500-900 MHz Power Window

## Question

The isolation experiment (`reports/addsub_isolation_experiment`) found that the decomposable
AddSub d4 is 84-99% worse than a gated fixed bank from 500 to 900 MHz, against 13-22% below and
14-21% above. It proposed three fixes. This experiment implements all three, sweeps them over
the same 12 targets, and checks whether they close the window.

## What was built

`rtl/fu_add_sub_window_fix.sv`. Every variant uses the ports, mode and `op_sel` encoding of
`fu_add_sub_d2/d4/d8`. Tiers are parameters (d2: `EN32=1,EN16=0,EN8=0`, d4: `1,1,0`, d8: `1,1,1`),
so each variant is synthesized as d2, d4 and d8.

| Design | Fix | Structure |
|---|---|---|
| `addsub_part_d*` (`fu_add_sub_part`) | 1, partitioned adder | One `+` over the operands widened by a guard bit at each lane boundary the tier can break. A guard bit passes the carry on (1, 0) or replaces it with the lane's carry-in (c, c), so DC sees a single adder and chooses its architecture per target. |
| `addsub_blkinc_d*` (`fu_add_sub_blkinc`) | 2, lane-block carry-increment | Blocks as wide as the narrowest lane (32, 16 or 8 bits), each one adder with carry-in 0; block carries from the blocks' generate/propagate; each block adds its carry-in with an incrementer. The longest adder is one block, as in the bank's narrowest unit. |
| `addsub_pipe_d*` (`fu_add_sub_pipe`) | 3, 64-bit mode in two cycles | Fix 1 built as two separate 32-bit-wide adders. A 64-bit lane's upper half is added with carry-in 0, and its carry-in is added in a second, clock-gated register stage. No single-cycle path is longer than 32 bits. 64-bit operations have latency 2 (throughput 1); other modes have latency 1. |

**Verification:**
- `rtl/tb_fu_add_sub_window_fix.sv` checks every variant and tier against the shared lane golden
  (`rtl/add_sub_lane_gold.svh`, now also used by the existing AddSub testbenches). It covers
  40,000 random operations in runs of one mode. The pipelined unit is checked one cycle later in
  64-bit mode, back to back, plus a backpressure stall.
- Five deliberate bugs are all caught: guard pass bit, block propagate, dropped carry across bit
  32 (in both the original and the final split), stall handling.
- Gate level: all 36 pipelined netlists (3 tiers x 12 targets, timed and zero-delay, every
  supported mode) match the golden on all 215,568 sampled outputs. Outputs are sampled at 99% of
  each period; the two netlists that close within 0.5 ps of their period (d8 at 600 and 900 MHz)
  are sampled at 99.9%.

## Flow

- **Synthesis:** same as the isolation experiment (SAED14nm RVT TT 0.8 V 25 C,
  `synth/syn_rerun.tcl`, one `dc_shell` per design and target, `CLOSURE=1`). All 108 runs met
  their target on the first compile.
- **Registered designs** (only `fu_add_sub_pipe`):
  - DC also gets a clock at the same period (zero input/output delay) and inserts clock gating.
  - Each clock gate drives at most 16 flops, standing in for clock-tree leaf buffers. Otherwise
    the wire-load model sizes one 65-sink clock net at about 1.6 pF.
  - The timed simulation uses an ideal clock: zero delay on the clock-gate cells and nets, as DC
    timed it.
  - The testbench generates one clock cycle per operation, ending at an absolute time.
  - These rules live in `syn_rerun.tcl` and `run_primepower.py`. The testbench for unclocked
    designs is unchanged (checked byte for byte).
- **Power:**
  - PrimePower with the shared stimulus, timed and zero-delay, for all 108 netlists.
  - A diagnostic third run, `HOLD_OPS=1`, holds every `op_sel` bit at 0, so every lane adds on
    every operation. It covers d4, d8, their three fixes and the bank, at every target
    (`primepower_ops_held/`, 156 runs).

## Files

| File | Contents |
|---|---|
| `addsub_window_fix_ppa.csv` | area, leakage, timing, cell counts per fix design and target |
| `addsub_window_fix_power.csv` | per fix design, target and mode: timed, zero-delay and ops-held PrimePower |
| `addsub_window_fix_savings.csv` | each fix, and the original segmented tiers, against the DesignWare bank per target and mode and mode-weighted; columns `timed_*`, `zero_delay_*`, `ops_held_*` |
| `raw/` | DC and PrimePower reports, `cells.txt`; `primepower_ops_held/` also for the segmented tiers and the bank |

`reports/collect_addsub_window_fix.py` builds the tables using the isolation experiment's
`collect()`. The bank and segmented-tier data come from `reports/addsub_isolation_experiment/raw`
and `reports/3rd_run/raw`. Netlists are not kept (`NETLIST=1` regenerates them).

## Result 1: none of the three fixes closes the window

d4 against the gated DesignWare bank, mode-weighted, timed (`addsub_window_fix_savings.csv`):

| Target (MHz) | 100 | 400 | 450 | 500 | 550 | 600 | 700 | 800 | 900 | 1000 | 1500 | 2000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Segmented (original) | -22 | -17 | -13 | -95 | -99 | -98 | -84 | -99 | -86 | -14 | -19 | -21 % |
| Fix 1, partitioned | -23 | -19 | -104 | -159 | -95 | -94 | -79 | -97 | -85 | -14 | -26 | -54 % |
| Fix 2, block-increment | -204 | -160 | -164 | -193 | -197 | -180 | -122 | -156 | -124 | -38 | -78 | -51 % |
| Fix 3, pipelined 64-bit | -117 | -103 | -96 | -112 | -103 | -98 | -78 | -120 | -140 | -45 | -68 | -76 % |

| d4 area saving (MHz) | 100 | 400 | 450 | 500 | 550 | 600 | 700 | 800 | 900 | 1000 | 1500 | 2000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Segmented | 70 | 68 | 65 | 58 | 57 | 58 | 57 | 57 | 56 | 66 | 63 | 60 % |
| Fix 1 | 70 | 69 | 46 | 40 | 53 | 54 | 55 | 55 | 55 | 66 | 62 | 53 % |
| Fix 2 | 50 | 29 | 28 | 29 | 28 | 29 | 38 | 37 | 42 | 56 | 41 | 43 % |
| Fix 3 | 35 | 34 | 36 | 38 | 39 | 38 | 40 | 32 | 25 | 42 | 37 | 38 % |

d8 and d2 behave the same way (see the CSV).

- **Fix 1** is the segmented design again. Below 450 MHz it is the same ripple adder (0.93 pJ per
  operation). Above, it becomes a fast adder at 1.5-2.3 pJ, one target earlier than the segmented
  core (450 MHz). It glitches just as much: the single `+` did not behave like the DesignWare unit.
- **Fix 2** costs about 2.4x the segmented design at every target, even at 100 MHz (2.28 against
  0.93 pJ), and zero-delay power doubles too, so this is useful switching rather than glitches.
  DC does not build its blocks as ripple adders (14 full-adder cells of 472, against 60 of 186),
  and the separate block propagate, block carries and incrementer add a layer of switching
  logic per bit.
- **Fix 3** works as intended on timing. It stays a ripple adder through 700 MHz (62 full-adder
  cells), so it has no 500 MHz jump. But it carries a constant overhead that outweighs the gain:
  - narrow modes: 1.4-1.5 pJ against 0.9 pJ for the segmented ripple design. Almost all of it is
    combinational (output select and split halves); the gated clock costs 0.01 pJ in these modes;
  - 64-bit mode: about 2.0 pJ, from 66 flops and their gated clock;
  - area: about 120 um2 more at 100 MHz.

  It ends up flat at about -100% from 100 to 600 MHz.

## Result 2: what actually drives the window

The isolation experiment attributed half or more of the window to glitching in the segmented
adder structure (eight 8-bit adds joined by carry-in muxes). **Fix 1 disproves that.** The
partitioned adder has no blocks and no muxes, and glitches as much.

The ops-held diagnostic shows the real split. Energy per operation, timed, random op per
operation (the study stimulus) versus every op held at add:

| 600 MHz | Random ops | Ops held |
|---|---:|---:|
| segmented d4, 64-bit / 2x32 / 4x16 | 1.54 / 1.53 / 1.51 pJ | 0.93 / 0.91 / 0.88 pJ |
| partitioned d4, 64-bit | 1.51 | 0.96 |
| DesignWare fixed 64 | 0.89 | 0.86 |
| DesignWare fixed 32x2 (ripple) | 0.73 | 0.47 |
| DesignWare fixed 16x4 (ripple) | 0.72 | 0.45 |

d4 against the gated bank, mode-weighted, ops held:

| Target (MHz) | 100 | 400 | 450 | 500 | 550 | 600 | 700 | 800 | 900 | 1000 | 1500 | 2000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Segmented, random ops (as above) | -22 | -17 | -13 | -95 | -99 | -98 | -84 | -99 | -86 | -14 | -19 | -21 % |
| **Segmented, ops held** | **+9** | **+6** | **+2** | **-60** | **-64** | **-61** | **-57** | **-58** | **-61** | **+26** | **+16** | **+15 %** |

1. **The add/subtract select is the glitch source.**
   - The stimulus changes each lane's op on every operation.
   - In the decomposable unit, each 8-bit block's select reaches its operand XORs through the lane
     decode, later than the operands. The inverted operand then switches twice per operation, and
     a fast adder propagates both waves.
   - With the op held, d4's fast form (0.93 pJ) costs about the same as DesignWare's fixed 64-bit
     unit (0.86 pJ), and the window gap shrinks from -98% to -61%.
   - DesignWare's `DW01_addsub`, which takes the op as a port, barely notices a toggling op (0.89
     against 0.86 pJ).
2. **The rest of the window is the speed class, and it is inherent.**
   - Even with clean ops, d4 must be a 64-bit-capable fast adder above 450 MHz (0.83-0.98 pJ in
     every mode).
   - Meanwhile the bank's 32x2 and 16x4 stay ripple adders at 0.45-0.49 pJ until 900 MHz-1 GHz.
   - That alone makes d4 about 60% worse against a gated bank in the window.
   - Fix 3 was the one fix aimed at this. It removes the jump but costs more than the jump in
     registers, clock and output selection.
3. **Outside the window, with clean ops, the decomposable unit beats the gated bank:**
   - +2 to +9% up to 450 MHz;
   - +15 to +26% from 1 to 2 GHz, where the bank's 32x2 has itself become a fast adder.

   The 13-22% loss measured outside the window comes from the random-op stimulus, not from the
   datapath.

## Conclusions

1. None of the three rewrites fixes the window. Fix 1 changes nothing, fix 2 doubles switching
   everywhere, and fix 3 trades the 500 MHz jump for a larger constant overhead.
2. The window has two causes:
   - **The op select arriving late at a fast adder.** This is worth about a third of the gap at
     500-900 MHz, and all of the 13-22% loss outside the window.
   - **The speed class.** One shared adder must be fast at the widest lane's target, while the
     bank's narrow units stay ripple. This is about -60% in the window, and inherent to a
     single-cycle shared 64-bit adder.
3. What would reduce the window further:
   - **For the op-select part:** keep the add/subtract select off the late path. That means a
     per-lane op that is stable across operations (as for most vector instructions), the
     inversion inside the adder as in `DW01_addsub`, or the lane op replicated per block before
     the FU, as was done for mode decode.
   - **For the speed-class part:** only a cheaper second cycle for 64-bit operations would help
     (no output select on the narrow path, flops shared with an existing pipeline register). As a
     standalone FU, the register and clock cost exceeds the saving.
   *Follow-up (`reports/addsub_spike_experiment`):* replicating the lane op per block before the
   FU fixes the op-select part. The speed-class part is also removable without a second cycle: a
   carry-select at bit 32, whose duplicate upper adder only switches for 64-bit lanes, holds
   -7..-28% against the gated bank from 500 to 800 MHz.
4. **For reporting:** the gated-bank power result for AddSub depends on how often the op changes.
   - With an op that changes every operation, the original numbers stand.
   - With a stable op, the decomposable unit matches or beats the gated bank everywhere except
     500-900 MHz, where it is about 60% worse.

## Caveats

- **Clock network (fix 3):** the clock network is modelled with DC's clock gating, at most 16
  flops per gate, plus the flow's wire-load model and an ideal clock in simulation. There is no
  clock-tree synthesis, so the clock power of fix 3 is an estimate under the same wire-load model
  as every other net.
- **Fix 3 changes the FU's contract:**
  - latency 2 for 64-bit lanes;
  - leaving 64-bit mode with a result still in the stage drops it, so a scheduler must drain the
    stage first.

  The DesignWare bank it is compared with is single-cycle.
- **The ops-held stimulus** is the extreme case (every lane always adds). Real workloads sit
  between it and the study stimulus.
