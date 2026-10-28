# AddSub + Min/Max Side Function: Rebuilding Min/Max on the AddSub Carry Network

## Question

In the third run (`reports/3rd_run`, Section 5), the AddSub with a Min/Max side function
(`rtl/fu_add_sub_minmax_gen.sv`) was already worse than a separate AddSub plus Min/Max from 500 MHz:
area −9% at 500 MHz and −93% at 2 GHz (d4). Its energy was also high at 100 MHz: 1.58 pJ per AddSub
operation against 0.91 pJ for the AddSub alone. Min/Max should be close to free next to an AddSub,
since the subtraction it needs is already there, and the savings should only turn negative somewhere
between 1 and 2 GHz.

This experiment:
- finds why the original costs so much;
- rebuilds the side function so that every control stays a runtime input and the circuit is the same
  in every mode;
- tries three ways of pipelining it.

## Why the original costs so much

`fu_add_sub_minmax_gen.sv` derives Min/Max from the subtraction *result*:

1. **Equality from the sum.** `zero_run` ORs every difference bit, block by block. The sum bits are
   the latest signals in the unit, so the compare waits for all of them and then chains.
2. **No isolation.** In AddSub mode the 64-bit A/B select (`minmax_out`) still switches on every
   operation, and so do the zero chain and the compare. A second 64-bit mux (`out_data = is_min_max ? ...`)
   follows.
3. **A serial select chain** from the top block down (`choose_b`).
4. **The original AddSub's late op decode**, which the spike experiment showed doubles adder
   switching (`reports/addsub_spike_experiment`).

At 2 GHz this path forced a 805 µm² unit, against 418 µm² for the separate pair.

## The new structure (`rtl/fu_add_sub_mm.sv`)

**The comparison comes from the carry network.** Min/Max computes A − B in every lane, exactly as
AddSub's subtract does: B inverted, carry-in 1. For A + ~B + 1:
- the carry out of a lane is **A ≥ B** (unsigned);
- a signed lane whose top bits differ is decided by B's sign: A ≥ B exactly when B is negative.

No sum bit, equality test or extra adder is needed. Each lane's result is one small gate on its
carry out (`ge`), routed to the lane's bytes through the one-hot lane width (`lane_ge`). A byte then
takes B when A ≥ B for min, or when A < B for max (`take_b = lane_ge ^ max_sel`). Ties need no rule:
A and B are the same value.

**One AND-OR per output bit.** Each output bit is the sum gated by `~is_min_max`, OR'd with A and B
gated by the byte's choice. This replaces the original's zero chain, serial select and two muxes.

**Per-block controls.** `sub_sel[i]` and `max_sel[i]` arrive per 8-bit block, prepared before the FU
like the left-edge mode decode and the spike experiment's replicated op. The B inversion is then
driven straight from a pin. For Min/Max the issuing logic sets `sub_sel` to all ones: every lane
subtracts.

**Same unit, both sides of the comparison.** `MINMAX = 0` is the AddSub alone, so fused minus
AddSub-alone is exactly the side function's cost. Both adders from the spike experiment are
available: `ARCH = 0` segmented, `ARCH = 1` carry-select at bit 32. A guard bit's sum supplies the
lane carry inside a partitioned half.

**Pipelining (`PIPE`), all with latency 1 for every operation:**

| PIPE | Structure | Design names |
|---|---|---|
| 0 | combinational | `mm_seg_*`, `mm_csel_*` |
| 1 | output register | `*o_*` |
| 1 + `RETIME=1` | the same register, retimed into the logic by DC | `*p_*` |
| 2 | **late select:** the register holds the sum, or A for Min/Max; B and the 8 choice bits load only for Min/Max (clock-gated otherwise); a 2:1 mux per bit follows | `mm_*l_*` |

`fu_min_max_piped` puts the decomposable Min/Max (`fu_min_max_gen.sv`) behind the same register, so
the pipelined pair is built the same way.

Mode, function, signedness and lane ops are runtime inputs in every variant. The adder (`ARCH`), the
tier (`EN*`) and the register stage (`PIPE`) are chosen at design time, like the tier. No variant
changes its circuit when the lane width changes.

## What the side function costs, and its floor

**At 100 MHz both adders are ripple:**
- the AddSub alone is 100 µm², made of 61 full adders and 62 inverting muxes for the B inversion;
- the fused unit is 171 µm².

The difference is the output stage: choosing one of three sources (sum, A, B) per bit costs at
least one AO222-class cell, about 0.8 µm² per bit. That's more than half the AddSub. **So in area
the side function cannot be "virtually free" next to such a small adder.** It can be cheaper than a
separate Min/Max (96–142 µm²), which is what gives the savings.

**Three output stages were tried (d4).** Energy is AddSub / Min/Max mode in pJ; area in µm². These
iteration runs are not kept in `raw/`; only the flat AND-OR is in the final RTL.

| Output stage | 100 MHz | 2 GHz |
|---|---|---|
| Flat AND-OR (kept) | 1.17 / 1.24, 171 | 1.87 / 2.54, 469 |
| A, B and the sum each through an isolation-gate module | 1.22 / 1.27, 204 | 1.76 / 2.75, 476 |
| A and B through isolation gates, the sum flat | 0.96 / 1.41, 198 | 1.75 / 2.84, 497 |

The isolation modules did silence A and B: their gates drew 2 nW in AddSub mode. But the sum then
passes through one or two extra gates, which switch with every sum glitch, and the kept hierarchy
costs area. The flat version is smallest and best in Min/Max mode, so it was kept.

Zero-delay runs show where the fused unit's extra AddSub-mode energy goes at 100 MHz: 0.67 against
0.34 pJ without any glitches. So it's real switching in the select, not glitches.

**Above 500 MHz a second cost appears: the speed class.** The fused unit's longest path is the carry,
then the compare, then a fan-out to up to 64 select bits. DC therefore builds a faster adder than the
AddSub alone needs, and that costs energy in AddSub mode too.

The late-select pipeline removes exactly this: ahead of its register the unit is the AddSub plus an
8-bit compare.

## Results

Every design was synthesized at 100 MHz, 500 MHz, 1 GHz, 1.5 GHz and 2 GHz (SAED14 RVT TT 0.8 V
25 °C, `synth/syn_rerun.tcl`, one DC session per design and target). It was simulated in PrimePower
with the shared stimulus: a random op, sign and lane op per operation; mode held for each run; each
function in its own run. **All 230 netlists met their target on the first compile.**

How to read the tables:
- **Pair:** the AddSub alone and the decomposable Min/Max (m2 for d2, m4 for d4 and d8). Single-cycle
  pair units come from `3rd_run/raw`; registered ones from this experiment, with the same register
  stage.
- **Each unit uses its own lower-energy adder** (`addsub_minmax_selected.csv`). Every adder is in
  `addsub_minmax_savings.csv`.
- **"Both units active":** the pair's two units both switch, as in a bank without operand isolation.
- **"Gated pair":** only the unit serving the function switches.
- Energy is mode-weighted (64/32/16 = 25/50/25%). **Positive means the fused unit saves.**

#### d4 (64, 2×32, 4×16)

| Saving against the separate pair (%) | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---|---|---|---|---|
| **Area: original** | +12 | −9 | −45 | −54 | −93 |
| **Area: new, single-cycle** | +13 | +2 | +5 | 0 | −26 |
| **Area: new, output register** | +28 | +16 | +22 | +13 | −12 |
| AddSub energy, both units active: original | +9 | −10 | −17 | −36 | −50 |
| AddSub energy, both units active: new, single-cycle | +21 | +23 | +34 | +23 | +10 |
| AddSub energy, both units active: new, output register | +35 | +35 | +42 | +35 | +24 |
| Min/Max energy, both units active: original | +44 | +16 | +2 | −21 | −53 |
| Min/Max energy, both units active: new, single-cycle | +16 | +21 | +13 | −6 | −23 |
| Min/Max energy, both units active: new, output register | +33 | +34 | +30 | +17 | +5 |
| AddSub energy, gated pair: original | −72 | −83 | −111 | −105 | −122 |
| AddSub energy, gated pair: new, single-cycle | −77 | −64 | −47 | −36 | −55 |
| AddSub energy, gated pair: new, output register | −35 | −32 | −23 | −19 | −38 |
| Min/Max energy, gated pair: original | −19 | −110 | −119 | −258 | −370 |
| Min/Max energy, gated pair: new, single-cycle | −52 | −49 | −57 | −143 | −195 |
| Min/Max energy, gated pair: new, output register | −28 | −29 | −33 | −84 | −112 |

#### d2 (64, 2×32)

| Saving against the separate pair (%) | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---|---|---|---|---|
| **Area: original** | +12 | −10 | −27 | −41 | −89 |
| **Area: new, single-cycle** | +19 | 0 | +4 | +9 | −26 |
| **Area: new, output register** | +31 | +17 | +20 | +19 | −9 |
| AddSub energy, both units active: original | +2 | −18 | −11 | −34 | −53 |
| AddSub energy, both units active: new, single-cycle | +25 | +12 | +26 | +31 | +13 |
| AddSub energy, both units active: new, output register | +37 | +31 | +39 | +37 | +26 |
| Min/Max energy, both units active: original | +37 | +6 | +1 | −19 | −47 |
| Min/Max energy, both units active: new, single-cycle | +19 | +25 | +1 | +2 | −22 |
| Min/Max energy, both units active: new, output register | +35 | +33 | +25 | +19 | +3 |
| AddSub energy, gated pair: original | −79 | −99 | −86 | −107 | −141 |
| AddSub energy, gated pair: new, single-cycle | −49 | −83 | −49 | −21 | −56 |
| AddSub energy, gated pair: new, output register | −25 | −39 | −24 | −17 | −37 |
| Min/Max energy, gated pair: original | −40 | −129 | −146 | −241 | −304 |
| Min/Max energy, gated pair: new, single-cycle | −62 | −44 | −97 | −129 | −177 |
| Min/Max energy, gated pair: new, output register | −31 | −32 | −47 | −73 | −112 |

#### d8 (64, 2×32, 4×16, 8×8; the Min/Max of the pair is m4)

| Saving against the separate pair (%) | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---|---|---|---|---|
| **Area: original** | +7 | −10 | −20 | −91 | −152 |
| **Area: new, single-cycle** | +11 | +3 | −1 | −14 | −27 |
| **Area: new, output register** | +26 | +19 | +23 | +1 | −17 |
| AddSub energy, both units active: original | +7 | −6 | −2 | −56 | −84 |
| AddSub energy, both units active: new, single-cycle | +17 | +21 | +28 | +5 | −3 |
| AddSub energy, both units active: new, output register | +33 | +35 | +42 | +23 | +14 |
| Min/Max energy, both units active: original | +40 | +24 | +17 | −32 | −78 |
| Min/Max energy, both units active: new, single-cycle | +15 | +20 | +11 | −17 | −20 |
| Min/Max energy, both units active: new, output register | +32 | +35 | +30 | +10 | +3 |
| AddSub energy, gated pair: original | −74 | −71 | −73 | −133 | −165 |
| AddSub energy, gated pair: new, single-cycle | −75 | −61 | −57 | −66 | −70 |
| AddSub energy, gated pair: new, output register | −37 | −28 | −22 | −40 | −55 |
| Min/Max energy, gated pair: original | −30 | −103 | −103 | −304 | −487 |
| Min/Max energy, gated pair: new, single-cycle | −62 | −58 | −65 | −174 | −204 |
| Min/Max energy, gated pair: new, output register | −33 | −31 | −35 | −101 | −118 |

#### d4 energy per operation (pJ) and area (µm²)

| Design: AddSub / Min/Max / area | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---|---|---|---|---|
| Fused, original | 1.58 / 0.97 / 174 | 2.63 / 2.00 / 279 | 3.31 / 2.79 / 440 | 3.43 / 3.05 / 529 | 3.99 / 4.05 / 805 |
| Pair, original | 0.91 / 0.81 / 198 | 1.44 / 0.95 / 256 | 1.57 / 1.27 / 304 | 1.67 / 0.85 / 344 | 1.80 / 0.86 / 418 |
| Fused, single-cycle | 1.17 / 1.24 / 171 | 1.38 / 1.42 / 247 | 1.53 / 2.00 / 280 | 1.51 / 2.07 / 314 | 1.87 / 2.54 / 469 |
| Pair, single-cycle | 0.66 / 0.81 / 197 | 0.84 / 0.95 / 253 | 1.04 / 1.27 / 294 | 1.10 / 0.85 / 315 | 1.20 / 0.86 / 371 |
| Fused, output register | 1.93 / 1.99 / 236 | 2.13 / 2.16 / 323 | 2.26 / 2.71 / 341 | 2.24 / 2.86 / 393 | 2.72 / 3.41 / 562 |
| Pair, output register | 1.43 / 1.56 / 327 | 1.61 / 1.68 / 385 | 1.83 / 2.04 / 436 | 1.88 / 1.55 / 452 | 1.98 / 1.61 / 503 |
| Fused, late select | 2.12 / 2.36 / 369 | 2.15 / 2.38 / 376 | 2.17 / 2.94 / 399 | 2.14 / 2.92 / 418 | 2.29 / 3.07 / 477 |
| Pair, late select (each unit's better register) | 1.43 / 1.56 / 327 | 1.61 / 1.65 / 386 | 1.83 / 2.04 / 436 | 1.88 / 1.37 / 431 | 1.98 / 1.42 / 481 |

#### The four pipelinings, d4 (area / AddSub vs gated / Min/Max vs gated, %)

| Pipelining | 100 MHz | 500 MHz | 1 GHz | 1.5 GHz | 2 GHz |
|---|---|---|---|---|---|
| none | +13 / −77 / −52 | +2 / −64 / −49 | +5 / −47 / −57 | 0 / −36 / −143 | −26 / −55 / −195 |
| output register | +28 / −35 / −28 | +16 / −32 / −29 | +22 / −23 / −33 | +13 / −19 / −84 | −12 / −38 / −112 |
| retimed register | +28 / −35 / −26 | +21 / −31 / −52 | +26 / −26 / −29 | −4 / −52 / −139 | −24 / −70 / −176 |
| late select | −13 / −49 / −52 | +3 / −33 / −44 | +8 / −18 / −44 | +3 / −14 / −113 | +1 / −16 / −116 |

## Findings

1. **The boundary moved from 500 MHz to between 1.5 and 2 GHz.**
   - Single-cycle area saving stays at or above 0% up to 1.5 GHz for d2 and d4. For d8 it holds to
     500 MHz, then falls to −1% at 1 GHz and −14% at 1.5 GHz.
   - With both units of the pair active, AddSub energy saves through 1.5 GHz (2 GHz for d2 and d4),
     and Min/Max energy through 1 GHz.
   - The original went negative at 500 MHz in area and AddSub energy.
2. **The side function's compare is free; its output select is not.** No comparator remains: the
   compare is a gate per lane on the existing carries. What remains is a three-source output select
   (≥ 0.8 µm² per bit) and, above 500 MHz, a faster adder to fit the compare and fan-out into the
   cycle. That's why savings come from replacing a whole Min/Max unit, not from the side function
   costing nothing.
3. **Against a gated pair, the fused unit loses in every configuration.** Its AddSub operations carry
   the output select, and its Min/Max operations run the whole adder where the standalone Min/Max runs
   only comparators. This matches the third run's finding that every decomposable family except FP
   Compare uses more energy per operation than a gated bank. The redesign makes the loss much
   smaller: AddSub −72..−122% → −19..−38% with an output register, d4.
4. **Pipelining moves every savings figure up, by sharing the register.** With an output register on
   both sides (latency 1 everywhere):
   - d4 area saving is +28 / +16 / +22 / +13 / −12%;
   - energy against both units active is positive at every target, in both functions;
   - against the gated pair, the AddSub loss halves.

   The mechanism is simple. The pair needs two 64-bit registers, the fused unit one (65 flops and
   4 clock-gate latches: about 65 µm² and 0.8 pJ per operation each, d4). This is a system argument:
   it holds when each unit would otherwise register its own result.
5. **Retiming does not help the fused unit at high frequency.** DC retimed the d4 register to 246
   flops at 2 GHz (602 µm²) to carry A and B past the compare, against 65 for the AddSub alone. From
   1.5 GHz it is worse than the plain output register.
6. **Late select removes the speed class, at the price of B's register.** Ahead of its register the
   fused unit is the AddSub plus an 8-bit compare. In AddSub mode its loss against the gated pair is
   the smallest of all variants from 1 GHz: −14 to −18% (d4). It holds area at +1 to +8% from
   500 MHz to 2 GHz, the only variant still non-negative at 2 GHz. B's 64 flops (clock-gated off in
   AddSub mode) make it the worst choice at 100 MHz (−13% area), where the adder needs no help.
   At 100 MHz DC also built its adder without full-adder cells (190 NAND2, 125 NOR2), which switches
   more. Late select is a design for high targets.
7. **Which form to build:**
   - **If the result is not registered at the FU:** single-cycle, segmented adder. The boundary is at
     about 1.5 GHz.
   - **If each unit's result would be registered anyway:** output register up to 1.5 GHz, late
     select at 2 GHz.

## Verification

- **RTL:** `rtl/tb_fu_add_sub_mm.sv` checks every ARCH × MINMAX × tier × PIPE instance and the
  pipelined Min/Max (m2, m4) against the shared lane golds (`add_sub_lane_gold.svh`, and the new
  `min_max_lane_gold.svh`, which `tb_fu_add_sub_minmax_gen.sv` now uses too).
  - 769,066 checks, with a new mode, function, signedness and lane ops every operation;
  - directed cases: carry and borrow chains, ties, sign boundaries, operands differing only in one
    bit;
  - stalls in both functions.
- **Planted bugs:** the testbench caught all 13, each planted in the final RTL:
  - signed rule on A;
  - wrong lane route;
  - off-by-one guard carry;
  - missing carry-select carry;
  - inverted min/max;
  - no stall hold;
  - wrong lane start;
  - A not gated off;
  - sum not gated off;
  - stale late-select choice;
  - late-select register holding the sum for Min/Max;
  - loading during a stall;
  - wrong byte's choice.
- **Gate level:** every one of the 230 netlists was simulated with its SDF delays, a new random mode,
  function, sign and op every clock period, and outputs checked against the golds at 99.9% of the
  period (pipelined designs one cycle later, with the ideal clock the power flow uses).
  - 229 netlists: 0 errors in 10,000 operations each; 50% (d2), 66% (d4) or 75% (d8) of operations
    follow a mode change.
  - `mm_seg_d8` at 1 GHz, which DC closed with 0 ps slack, gives 1,484 errors at 1.000 ns and 0 at
    1.010 ns: the SDF simulation and DC's timing differ by under 1% on that path.
- **Collector cross-check:** `collect_addsub_mm.py` reproduces the third run's side-function
  figures exactly (−72.127%, +8.733%, −18.946%, +44.082% at 100 MHz, d4).
- **Coverage:** every PrimePower run annotated 100% of nets.

## Flow changes

- **`synth/syn_rerun.tcl`:**
  - jobs for every design here;
  - `RETIME=1` flattens a registered design and compiles with `-retime`.
- **`synth/run_primepower.py`:**
  - **Inputs held in only some functions:** the fused unit holds `sub_sel` at all ones for Min/Max
    and drives it from the stimulus for AddSub.
  - **Per-block controls:** `sub_sel` and `max_sel` get the replicated-op mapping.
  - **`ideal_clock()` fix:** it now also zeroes clock gates inside a sub-design. With the hierarchy
    kept (output register, late select), DC puts them at `<instance>/clk_gate_...`, and their delays
    had skewed the clock.
  - **No effect on earlier results:** testbenches for every earlier design are byte-identical, and
    the SDFs of flat designs are unchanged.
- **`reports/collect_rerun.py`:** catalog entries for the new designs.
- **`reports/collect_mode_left.py`:** mode probabilities for the new family.

## Caveats

- **The per-block controls are prepared before the FU**, as in the spike experiment:
  - `sub_sel` is the lane's subtract replicated per block, all ones for Min/Max;
  - `max_sel` is the lane's max replicated per block.

  The issuing logic's cost (muxes into an existing register) is not in these numbers.
- **The gated-pair comparison stays negative** in every configuration (Finding 3).
- **Single-compile noise** moves single points by 10–20 points (e.g. d4 Min/Max at 1 GHz in the third
  run's m4). Read trends across the five targets.
- **Mode is held for each simulation,** as in every earlier run, so no figure includes mode-switch
  energy. The gate-level checks do switch mode every cycle.
- **Pair baselines:** the single-cycle pair uses the third run's `minmax_m2`/`m4` and this
  experiment's AddSub alone (the spike-fix AddSub, which is better than the third run's `addsub_dN`).
  The original rows compare like for like from the third run.

## Files

| File | Contents |
|---|---|
| `addsub_minmax_ppa.csv` | area, leakage, timing, cells, full adders, flops and clock-gate latches per design and target |
| `addsub_minmax_power.csv` | PrimePower energy per operation per design, target, function and mode |
| `addsub_minmax_savings.csv` | per tier, target, pipelining and adder: the fused unit against the separate pair (area; energy per function against the gated pair and both units active), and the original |
| `addsub_minmax_selected.csv` | the same with each unit on its lower-energy adder (and, for the late-select pair, register form) |
| `raw/` | DC and PrimePower reports, `cells.txt` per netlist |

`reports/collect_addsub_mm.py` builds the tables. Netlists are not kept: `NETLIST=1` regenerates
them, one DC session per design and target with the repo's `alib-52` cache to reproduce them exactly.
