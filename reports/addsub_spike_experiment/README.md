# AddSub Spike Experiment: Removing the 500-900 MHz Gated-Bank Power Spike

## Question

The decomposable AddSub is 84-99% worse than a gated DesignWare bank from 500 to 900 MHz, against
13-22% below and above (`reports/addsub_isolation_experiment`). The window-fix experiment
(`reports/addsub_window_fix_experiment`) traced this to two causes:

- **the add/subtract select**, about a third of the gap;
- **the speed class**, about two thirds: a single-cycle 64-bit carry forces a fast adder from
  about 450 MHz, while the bank's 32x2 and 16x4 stay ripple adders.

This experiment varies every lever I could find, one at a time, to remove the spike.

## What was varied

`rtl/fu_add_sub_spike.sv` is one wrapper, `fu_add_sub_spike`, with independent knobs: `ARCH`,
`FLAT`, `REP_OP`. Tiers are `EN32/EN16/EN8`, as in `fu_add_sub_gen.sv`. The file also holds the
probe `fu_add_sub_spike_probe32x2`. Synthesis options are `STATIC_MODE` and `POWER_OPT` in
`synth/syn_rerun.tcl`; the stimulus option is `HOLD_OPS` in `synth/run_primepower.py`.

| # | Variable | Change | Design names | Outcome |
|---|---|---|---|---|
| 0 | reproduction | the original segmented structure rebuilt in the new file | `segser` | within 2-6 points of the original d4 (gated bank, four targets), area saving within 1 point |
| 1 | lane-op decode depth | flat decode: each block's op through one mode-selected mux instead of the serial chain | `segflat`, `csel` | **no effect** (identical to the serial decode) |
| 2 | adder architecture | carry-select at bit 32: separate 32-bit halves, plus a duplicate upper half with carry-in 1 whose operands are gated to zero except for 64-bit lanes | `cselser`, `csel` | removes the speed-class part at 500-700 MHz (ops held: -12% at 600 MHz, against -61%), but with random ops each operation pays the op-toggle glitch (-62%) |
| 3 | adder primitive | the bank's 32x2 function built five ways: inferred `+` (three-operand and guard forms), `DW01_add`, `DW01_addsub`, `DW_addsub_dx` | `probe0`-`probe4` | **no effect**: all five synthesize to the same 60-full-adder ripple design (0.73-0.74 pJ; 0.47 pJ with ops held) |
| 4 | DesignWare building blocks | the carry-select built from `DW_addsub_dx` halves and a `DW01_add` | `dwcselser`, `dwcsel`, `dwcselrep` | **worse** (see the DesignWare flag) |
| 5 | **op encoding at the FU boundary** | `op_sel` arrives replicated per 8-bit block (block i gets its lane's op, prepared before the FU like the left-edge mode decode), so each block's operand inversion and carry-in come straight from a pin | `segrep`, `cselrep`, `csel16rep`, `dwcselrep` | **removes most of the spike** (Result 1) |
| 6 | finer carry-select | select at every 16 bits; each upper segment has a gated duplicate | `csel16rep` | stays ripple to 1 GHz, but its 2x32 mode runs two duplicates (1.32 pJ); best only at 900 MHz (d8: 800-900 MHz) |
| 7 | mode timing | mode as a static configuration input (`set_false_path -from mode`) | `raw_static_mode/` | small: `cselrep` 600 MHz -19% -> -12%, 900 MHz -92% -> -82%; `segrep` and `csel16rep` unchanged |
| 8 | power-driven synthesis | input activity set before compile, `set_dynamic_optimization true`, total-power optimization, extra-high dynamic effort | (not kept) | **no effect**: all 20 netlists checked are byte-identical to the plain ones (total-power optimization needs DC's physical-guidance flow, PWR-1104) |
| 9 | stimulus | random op per lane per operation (the study), and every op held at add | all | brackets real workloads; used for the selection below |

### What the toggle counts showed (why variable 5 works)

Gate-level switching counts (SAIF), d4 in 2x32 mode at 400 MHz:

| Signal | Ops held | Random ops |
|---|---|---|
| inverted-operand nets (`b ^ sub`) | 0.50 toggles per operation | 0.96-1.01 |
| lane carry-ins | — | about 1.0 |
| the chain whose `sub` is `op_sel[0]` wired straight through | — | 0.75 |
| output bits, blocks 2-7 | 1.3 | 2.2 |
| output bits, bank 32x2 | 1.0 | 1.45 |

Any logic or buffering between `op_sel` and a block's inversion makes the inverted operand switch
twice per operation, and the adder evaluates both waves. Flattening the decode (variable 1) still
leaves a mux and buffers. Only taking the op straight from a pin (variable 5) removes the second
wave: `segrep`'s fast form then costs the same with random and held ops (0.95 against 0.96 pJ at
600 MHz).

## Result 1: d4 against the gated bank, mode-weighted

| Target (MHz) | 100 | 400 | 450 | 500 | 550 | 600 | 700 | 800 | 900 | 1000 | 1500 | 2000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Original, random ops | -22 | -17 | -13 | -95 | -99 | -98 | -84 | -99 | -86 | -14 | -19 | -21 % |
| Original, ops held | +9 | +6 | +2 | -60 | -64 | -61 | -57 | -58 | -61 | +26 | +16 | +15 % |
| `segrep`, random ops | +14 | +18 | +19 | -14 | -15 | -22 | -14 | -24 | -19 | +25 | +21 | +20 % |
| `segrep`, ops held | +12 | +9 | +9 | -57 | -57 | -66 | -62 | -63 | -65 | +21 | +17 | +20 % |
| `cselrep`, random ops | -24 | -17 | -16 | -28 | -24 | -19 | -7 | -16 | -92 | -12 | -15 | -12 % |
| `cselrep`, ops held | -33 | -31 | -31 | -18 | -14 | -10 | -8 | -11 | -124 | -5 | -17 | -13 % |

- **Replicated op encoding alone (`segrep`)** cuts the spike from -84..-99% to -14..-24%, and
  makes the unit beat the gated bank by 14-25% outside the window. But this holds only with
  random ops. With ops held the speed-class part remains (-57..-66%).
- **Replicated op plus carry-select at bit 32 (`cselrep`)** holds -7..-28% (random) and
  -8..-18% (held) from 500 to 800 MHz. It costs more than `segrep` outside the window. At
  900 MHz DC makes its 32-bit halves fast and it collapses. There only a plain 32-bit ripple
  fits, which the bank has and the carry-select's guard bits and select do not.

## Result 2: architecture selected per target

`addsub_spike_selected.csv`. For each tier and target, the selection picks the replicated-op
variant (`segrep`, `cselrep`, `csel16rep`) whose worse case over the two stimuli is best. This
makes the choice independent of how often the op changes. A generator would make it the same
way it picks a tier, per synthesis target.

| d4 (MHz) | 100 | 400 | 450 | 500 | 550 | 600 | 700 | 800 | 900 | 1000 | 1500 | 2000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Selected | seg | seg | seg | csel | csel | csel | csel | csel | csel16 | seg | seg | seg |
| vs gated, random ops | +14 | +18 | +19 | -28 | -24 | -19 | -7 | -16 | -51 | +25 | +21 | +20 % |
| vs gated, ops held | +12 | +9 | +9 | -18 | -14 | -10 | -8 | -11 | -49 | +21 | +17 | +20 % |
| vs all-active bank | 71 | 73 | 74 | 57 | 59 | 61 | 64 | 62 | 50 | 71 | 70 | 70 % |
| Area saving | 70 | 70 | 69 | 55 | 55 | 56 | 55 | 54 | 50 | 68 | 67 | 68 % |

The original's 500-800 MHz values were -95, -99, -98, -84 and -99% (random ops) against the
gated bank.

| Worst case in the window | 500-800 MHz | 900 MHz |
|---|---|---|
| d2 | -29% (random) / -15% (held) | -51% / -47% |
| d4 | -28% / -18% | -51% / -49% |
| d8 | -29% / -33% (450-700 MHz) | -68% / -57% at 800 MHz, -54% / -53% at 900 MHz |

Outside the window every tier beats the gated bank by 6-37%.

## Conclusions

1. **The biggest single fix is the op encoding.** If the FU receives each 8-bit block's op
   directly (the lane op replicated per block before the FU, as was already done for mode
   decode), the operand inversion no longer switches twice. The spike falls from -84..-99% to
   -14..-24% with random ops. Outside the window the decomposable unit then beats the gated bank.
2. **The carry-select at bit 32 removes the speed-class part from 500 to 800 MHz.** Its gated
   duplicate adder only switches for 64-bit lanes. With replicated op it holds -7..-28% in that
   range, whether ops change every operation or never.
3. **Selecting the architecture per target** (segmented below 500 MHz and from 1 GHz;
   carry-select from 500 to 800 MHz) removes the spike everywhere except 900 MHz. 900 MHz
   (800-900 MHz for d8) is the bank's last ripple target for its 32x2 (16x4 for d8's 8-bit
   lanes). Any mode logic in a 32-bit path pushes the decomposable unit past it. The 16-bit
   carry-select is the best option there, at about -50%.
4. **No effect:** decode flattening, the adder primitive, and DC's power-driven compile (byte-
   identical netlists). Treating mode as static gives a few points to the carry-select only.

## DesignWare flag

The carry-select built from DesignWare parts (`DW_addsub_dx` halves split at 16, `DW01_add`
duplicate) is worse than the same structure hand-written, at every target:
- d4 with replicated op: -56..-80% against the gated bank from 400 to 800 MHz, against
  -16..-19% for the hand-written `cselrep`;
- area about the same (140-315 against 164-296 um2).

| | |
|---|---|
| Pros | a library primitive for each half, with the 16-bit split handled inside the duplex adder |
| Cons | compile_ultra ungroups and re-architects the DesignWare parts (only 33 ripple full adders survive, against 94 hand-written), and the resulting mux-heavy logic glitches far more |

Used alone as fixed units, the DesignWare primitives match the inferred `+` exactly (variable 3).

## Files

| File | Contents |
|---|---|
| `addsub_spike_ppa.csv` | area, leakage, timing, cell counts per variant and target |
| `addsub_spike_power.csv` | timed, zero-delay and ops-held PrimePower per variant, target and mode |
| `addsub_spike_savings.csv` | each variant (and the original tiers) against the DesignWare bank, per target and mode and mode-weighted |
| `addsub_spike_selected.csv` | the per-target selection (Result 2) |
| `addsub_spike_static_mode_*.csv` | the same for variants synthesized with `STATIC_MODE=1` (`raw_static_mode/`) |
| `raw/`, `raw_static_mode/` | DC and PrimePower reports (`primepower/`, `primepower_zero/`, `primepower_ops_held/`) |

`reports/collect_addsub_spike.py` builds the tables using the isolation experiment's `collect()`;
the bank and original tiers come from the isolation and window-fix experiments and the third run.

Coverage:
- **Full 12-target sweep:** `segrep` and `cselrep` (d2, d4, d8).
- **Screened at 400, 600, 800 MHz and 1 GHz (d4):** `segser`, `segflat`, `cselser`, `csel`.
- **Screened at the same four targets (d2, d4):** `dwcselser`, `dwcsel`.
- **Also at 900 MHz (d2, d4):** `dwcselrep`.
- **`csel16rep`:** d4 at 400 MHz-1 GHz; d2 and d8 at 700-900 MHz.

Netlists are not kept (`NETLIST=1` regenerates them).

## Verification

- `rtl/tb_fu_add_sub_spike.sv` checks every `ARCH x FLAT` combination and every `REP_OP` variant,
  as tiers d2/d4/d8, and the five 32x2 probes against the shared lane golden (40,000 random
  operations plus directed carry-isolation cases). It caught all seven deliberate bugs:
  - wrong lane in the flat decode;
  - a missing carry-select;
  - a wrong upper-half carry-in (DesignWare variant);
  - a missing 16-bit split (DesignWare variant);
  - the wrong block for a replicated op;
  - ignoring the duplicate's carry in the 16-bit select;
  - a dropped carry-in in a probe.

  Removing the duplicate's carry-in gating passes, as it should: that gating only affects power.
- The replicated-op netlists match the golden at gate level under the power testbench's op mapping
  (0 mismatches in 96,000 outputs: d2, d4 and d8 `cselrep` and d4 `segrep` at 100 MHz, 600 MHz,
  900 MHz and 2 GHz, timed and zero-delay).
- Every run met its target on the first compile. Every PrimePower run annotated 100% of nets.

## Caveats

- **Replicated op changes the FU's interface:**
  - `op_sel[i]` is the op of the lane containing block i.
  - The issuing logic must replicate the lane op per block, which is wiring once mode is known.
  - The power testbench drives it from the same stimulus bits at the lane starts, so every lane
    sees the same op as in every other design.
- **The per-target selection uses two RTL architectures.** Either is one generator parameter;
  both are verified for every tier.
- **The stimuli are bounds.** Random ops per lane per operation and ops held at add bracket real
  workloads.
