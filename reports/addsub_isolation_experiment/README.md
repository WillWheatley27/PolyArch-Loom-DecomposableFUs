# AddSub Isolation Experiment: Why Gated-Bank Power Collapsed at 500 MHz

## Question

In the third run, the decomposable AddSub (d4) was 14-23% worse than a gated fixed bank at
100 MHz, 1 GHz, 1.5 GHz and 2 GHz, but 95% worse at 500 MHz (d8: 113% worse). This experiment
isolates the cause.

## What was run

All on SAED14nm RVT TT 0.8 V 25 C with the third-run flow (`synth/syn_rerun.tcl`,
`compile_ultra -area_high_effort_script -no_autoungroup`, `CLOSURE=1`, one fresh `dc_shell` per
design and target), and PrimePower with the shared stimulus (`synth/run_primepower.py`).

| Targets | Designs |
|---|---|
| 400 MHz, 600 MHz (new) | all AddSub tiers (d1, d2, d4, d8) and fixed units (64, 32x2, 16x4, 8x8) |
| 450, 550, 700, 800, 900 MHz (new, bracketing) | d4, d8 and every fixed unit |
| 100 MHz, 500 MHz, 1 GHz, 1.5 GHz, 2 GHz | the third run (`reports/3rd_run/raw`), unchanged |

Every design meets every target on the first compile. Two diagnostics were added:

- **Zero-delay simulation** (`ZERO_DELAY=1 synth/run_primepower.py`): the same netlist and stimulus
  simulated with no cell or wire delays, so nothing glitches. Timed minus zero-delay power is
  glitch power. Run for every design and target, including the third-run netlists (the 1 GHz and
  2 GHz ones were regenerated; DC is deterministic and all 16 reproduced the committed reports
  exactly).
- **Cell histograms** (`raw/<design>/<corner>/cells.txt`): the number of ripple full-adder cells
  (`ADDF`) shows whether DC built a ripple-carry adder or a faster structure.

## Files

| File | Contents |
|---|---|
| `addsub_isolation_ppa.csv` | area, leakage, timing, total cells and ripple full-adder cells per design and target |
| `addsub_isolation_power.csv` | timed and zero-delay PrimePower per design, target and mode; glitch power and share |
| `addsub_isolation_savings.csv` | d2/d4/d8 vs the fixed bank per target and mode, and mode-weighted (25/50/25): DC area and leakage, PrimePower against a gated and an all-active bank, timed and zero-delay |
| `raw/` | reports for the new targets and the look-ahead set; `primepower_zero/` and `cells.txt` for every target |

The look-ahead follow-up (below) adds the `addsub_la_*` designs to the PPA and power tables
(column `adder`) and two comparisons to the savings table (column `comparison`).

`reports/collect_addsub_isolation.py` builds the tables (timed data for the third-run targets
is read from `reports/3rd_run/raw`). Netlists are not kept; `NETLIST=1` regenerates them.

## Result 1: the bad window is 450-500 MHz to 900 MHz-1 GHz, not just 500 MHz

d4 against the gated bank, mode-weighted (`addsub_isolation_savings.csv`):

| Target | 100 | 400 | 450 | **500** | **550** | **600** | **700** | **800** | **900** | 1000 | 1500 | 2000 MHz |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Timed | -22 | -17 | -13 | **-95** | **-99** | **-98** | **-84** | **-99** | **-86** | -14 | -19 | -21 % |
| Zero-delay | -13 | -11 | -13 | -64 | -73 | -68 | -57 | -63 | -49 | +10 | +5 | +1 % |
| vs all-active bank | 59 | 62 | 63 | 35 | 34 | 35 | 39 | 35 | 38 | 57 | 54 | 55 % |
| Area saving | 70 | 69 | 65 | 58 | 57 | 58 | 57 | 57 | 56 | 66 | 63 | 60 % |

d8 behaves the same way, with the window starting one step earlier (450 MHz: -81%).

500 MHz was not an outlier; it was the only third-run target inside a window that spans
500-900 MHz.

## Result 2: the window is set by when each adder changes structure

Ripple full-adder cells / total cells, and timed energy per operation:

| Target (MHz) | d4 | fixed 64 | fixed 32x2 | fixed 16x4 |
|---|---|---|---|---|
| 100 | 60/186, 0.93 pJ | 62/261, 0.79 | 60/258, 0.74 | 56/250, 0.72 |
| 400 | 60/188, 0.94 | 62/265, 0.96 | 60/258, 0.74 | 56/250, 0.72 |
| 450 | 60/196, 0.93 | 61/274, 1.05 | 60/258, 0.74 | 56/250, 0.72 |
| **500** | **21/460, 1.46** | 21/398, 0.76 | 60/258, 0.74 | 56/250, 0.72 |
| 600 | 16/501, 1.54 | 7/490, 0.89 | 60/258, 0.74 | 56/250, 0.72 |
| 900 | 14/534, 1.57 | 0/566, 0.98 | 60/264, 0.83 | 56/250, 0.72 |
| **1000** | 12/551, 1.59 | 0/575, 0.99 | **0/757, 1.91** | 56/250, 0.72 |
| 2000 | 9/643, 1.89 | 0/593, 1.15 | 0/761, 1.95 | 4/491, 0.89 |

(d4 in 64-bit mode; its other modes are within 3%.)

- A ripple-carry adder's delay grows with the length of its carry chain. The ripple delays are
  d4 4.38 ns (a 64-bit chain plus lane-boundary carry-in muxes), fixed 64 3.53 ns, fixed 32x2
  1.83 ns and fixed 16x4 1.57 ns. Below about 450 MHz every unit stays ripple.
- **Between 450 and 500 MHz DC must rebuild d4 as a fast adder** (60 -> 21 ripple cells, 196 -> 460
  cells, 121 -> 155 um2), and its energy per operation jumps 57% (0.93 -> 1.46 pJ). d8 has more
  carry-in muxes on the chain and switches between 400 and 450 MHz.
- **The bank's narrow units stay ripple much longer**, because their carry chains are 2-4 times
  shorter: the fixed 32x2 up to 900 MHz (sized ripple), the fixed 16x4 up to 1.5 GHz.
- **At 1 GHz the DesignWare duplex 32x2 changes structure and becomes very expensive** (0 ripple
  cells, 263 um2, 1.91 pJ): more than d4 itself in 2x32 mode (1.57 pJ).

Inside the window the gated bank therefore pays cheap ripple energy for 3/4 of the operations
(2x32 and 4x16 modes), while d4 pays fast-adder energy for every operation. Below the window both
sides are ripple; above it the bank's 32x2 is as expensive as d4, which is the only reason the 1 GHz
to 2 GHz gated numbers look better. Per mode, d4 is 59-91% worse than the fixed 64-bit unit and
90-165% worse than the fixed 16x4 at every target from 500 MHz to 2 GHz; only the 2x32 comparison
flips (from -84..-118% to +8..+18%) when the bank's 32x2 changes structure.

## Result 3: what the extra energy is

Zero-delay simulation splits the energy per operation into useful switching and glitches:

| Comparison (500 MHz) | Decomposable | Fixed unit | Gap | Useful switching | Glitch |
|---|---:|---:|---:|---:|---:|
| d4 64-bit vs fixed 64 | 1.457 pJ | 0.762 | +0.695 | +0.179 | **+0.517** |
| d4 2x32 vs fixed 32x2 | 1.440 | 0.737 | +0.703 | +0.337 | +0.365 |
| d4 4x16 vs fixed 16x4 | 1.429 | 0.723 | +0.706 | +0.332 | +0.374 |

- **Against units of the same speed class** (d4 vs the fast DesignWare 64-bit adder), three
  quarters of the gap is glitch power: d4's fast form glitches 0.70 pJ per operation (48% of its
  energy), the DesignWare adder 0.18 pJ (24%). This holds from 500 MHz to 2 GHz.
- **Against the ripple narrow units**, the gap is half useful switching (a fast adder has many more
  internal nodes than a ripple adder) and half glitch.
- d4's own jump at 500 MHz (+0.53 pJ) is +0.22 pJ useful switching and +0.31 pJ glitch.

## Explanation in the RTL

`fu_add_sub_segmented` (in `rtl/fu_add_sub_gen.sv`) writes the 64-bit adder as eight separate 8-bit
additions joined by carry-in muxes:

```
cin[i] = is_start[i] ? sub_i : cout[i-1];
{cout[i], sum[i]} = a[i] + be[i] + cin[i];
```

1. **The widest lane sets the speed of every lane.** The 64-bit mode needs a carry across all eight
   blocks, so d4 must be a fast 64-bit adder at any target above about 450 MHz, even when it is
   running 2x32 or 4x16 operations whose carries stop after 32 or 16 bits. A dedicated 32x2 or 16x4
   unit only ever needs a 32- or 16-bit chain and stays a cheap ripple adder up to 0.9-1.5 GHz.
   This part is inherent to sharing one datapath across lane widths.
2. **The fast form glitches.** *Corrected by `reports/addsub_window_fix_experiment`.* This
   section first blamed the segmented structure (eight blocks joined by carry-in muxes). A
   partitioned rewrite with one `+` and no muxes glitches just as much, so that explanation was
   wrong.

   The glitch source is the add/subtract select. The stimulus changes each lane's op on every
   operation, and each block's select reaches its operand XORs through the lane decode, later
   than the operands. The inverted operand switches twice, and a fast adder propagates both
   waves. With every op held at add, d4's fast form costs about what DesignWare's fixed 64-bit
   unit does (0.93 against 0.86 pJ at 600 MHz). DesignWare's `DW01_addsub`, which takes the op as
   a port, barely notices a toggling op.

## Conclusions

1. The 500 MHz result is real and typical of 500-900 MHz, not an anomaly. Against a gated bank,
   the decomposable AddSub is 13-22% worse up to 450 MHz, 84-99% worse from 500 to 900 MHz,
   and 14-21% worse from 1 to 2 GHz.
2. The window opens when the decomposable adder must switch from ripple to a fast structure
   (450-500 MHz, earlier for d8) and closes when the fixed 32x2 has to do the same (900 MHz-1 GHz).
   The better gated numbers at 1-2 GHz come from the DesignWare duplex 32x2 becoming expensive,
   not from the decomposable unit improving.
3. Area, leakage and the all-active-bank savings follow the same window (area 65-70% -> 56-58%,
   all-active 59-63% -> 34-39%), so the window is visible in every metric, just most strongly in
   the gated-bank comparison.
4. Half or more of the extra energy is glitching. *Corrected:* it comes from the add/subtract
   select arriving late at a fast adder, not from the segmented structure. The partitioned rewrite
   proposed here, and two other fixes, were built and measured in
   `reports/addsub_window_fix_experiment`; none closes the window. With every op held at add, the
   gap shrinks from about -95% to about -60% in the window, and d4 beats the gated bank outside
   it. The remaining ~60% is the speed-class part (narrow fixed units staying ripple longer),
   which is inherent to sharing one single-cycle adder across lane widths.

For reporting AddSub power against a gated bank, quote it as a function of frequency (or
separately below 450 MHz, 500-900 MHz and 1-2 GHz) rather than as one number.

## Follow-up: one look-ahead architecture at every target

**Question.** If every unit used a look-ahead adder at every target, so nothing switches from
ripple to look-ahead, what happens to d4 against the gated bank?

**Forcing it.** No DC setting does this: in this DesignWare release the `+` operator maps to
DW01_add/addsub with only the flexible `pparch`/`apparch` architectures, which become ripple
chains at loose targets. `rtl/fu_add_sub_prefix.sv` therefore writes the adder explicitly as a
64-bit Sklansky parallel-prefix tree with lane carry-kill (the node feeding a lane start is
replaced by generate = the lane's carry-in, propagate = 0). The tiers `fu_add_sub_pd2/pd4/pd8`
and the fixed units `fu_add_sub_p64/p32x2/p16x4/p8x8` are the same core, the fixed units with
mode tied (same ports as the existing tiers and standalone units, so the stimulus is identical).
Each prefix combine is its own module instance: written flat, `compile_ultra`'s area recovery
folded the tree back into a 60-full-adder ripple chain at 100 MHz. With the instances
(and the flow's `-no_autoungroup`) every netlist has 0 ripple full-adder cells and nearly the
same cell count at every target (d4: 629 cells at 100 MHz, 660 at 2 GHz); DC only resizes.
`rtl/tb_fu_add_sub_prefix.sv` checks every tier and fixed unit against the lane golden (a copy
with the carry-kill removed gives 27,581 mismatches). All 7 designs met all 12 targets on
the first compile.

**d4 against the gated bank, mode-weighted:**

| Target (MHz) | 100 | 400 | 450 | 500 | 550 | 600 | 700 | 800 | 900 | 1000 | 1500 | 2000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Segmented vs DesignWare bank (above) | -22 | -17 | -13 | -95 | -99 | -98 | -84 | -99 | -86 | -14 | -19 | -21 % |
| **Look-ahead vs look-ahead bank, timed** | **-21** | **-22** | **-12** | **-13** | **-17** | **-7** | **-22** | **-23** | **-28** | **-15** | **-22** | **-55 %** |
| Look-ahead vs look-ahead bank, zero-delay | -15 | -15 | -15 | -9 | -17 | -10 | -13 | -16 | -15 | -12 | -15 | -16 % |
| Look-ahead vs look-ahead bank, all-active | 59 | 59 | 63 | 62 | 61 | 64 | 60 | 60 | 58 | 61 | 59 | 48 % |
| Look-ahead area saving | 62 | 61 | 61 | 62 | 61 | 61 | 61 | 61 | 60 | 60 | 58 | 55 % |
| Look-ahead d4 vs DesignWare bank, timed | -277 | -254 | -218 | -261 | -224 | -231 | -214 | -222 | -215 | -82 | -68 | -82 % |

Per mode (look-ahead vs look-ahead, timed; zero-delay in brackets): 64-bit -11..+6% (-6..+3%),
2x32 -3..-37% (-7..-19%), 4x16 -33..-55% (-32..-38%) from 100 MHz to 1.5 GHz; at 2 GHz -35%,
-54% and -84%.

- **The window disappears.** With one architecture everywhere, d4 costs 7-28% more power than
  the gated bank from 100 MHz to 1.5 GHz, with no 500-900 MHz collapse. Without glitches the cost
  is a flat 9-17%: that is the structural price of sharing one 64-bit adder. It sits almost
  entirely in the narrow modes: in 4x16 mode the shared unit still drives a 6-level, 64-bit
  tree and its cross-lane nodes, where the fixed 16x4 has four 4-level trees (489 cells vs 632).
- **2 GHz reopens part of the gap (-55%).** The 64-bit tree is two levels deeper than a 16-bit
  tree, so at 0.5 ns d4 is upsized (area +48% from 100 MHz) while the narrow fixed units still
  have slack. The speed-class effect remains; with one architecture it shows up only at the top
  target, as sizing.
- **Glitching is not the cause either way.** The explicit prefix designs glitch 44-52% of their
  energy (like the segmented d4); timed results move 5-15 points around the flat zero-delay
  numbers.
- **In absolute terms look-ahead everywhere is a bad trade.** The explicit tree costs about
  2.2-2.9 pJ per operation for d4 at every target, against 0.93 pJ for the segmented d4 below
  450 MHz and 1.5-1.9 pJ above it; area is 216-319 um2 against 102-276 um2. Against the
  DesignWare bank, look-ahead d4 is 214-277% worse below 1 GHz and 68-82% worse at 1-2 GHz. A
  ripple adder is the lowest-power adder whenever the target allows it, and the per-node module
  boundaries that keep the tree also stop DC from merging logic across nodes.
- **DesignWare flag.** At 1-2 GHz the DesignWare duplex `fu_add_sub_32x2` is larger than the
  hand-written prefix 32x2 (263-313 um2 vs 202-234 um2, leakage 0.09-0.13 vs 0.07-0.12 uW).
  Its energy per operation is lower at 1 GHz (1.91 vs 2.27 pJ), equal at 1.5 GHz (1.96 vs 1.97)
  and higher at 2 GHz (1.95 vs 1.76). Pro: one library call, and below 1 GHz it stays a cheap
  ripple adder that the prefix design cannot match. Con: at 1-2 GHz it is 25-35% larger, leaks
  more and, at 2 GHz, also uses more energy than a fixed-topology prefix adder.

**Conclusion.** The window was an artefact of the units changing architecture at different
targets. Held to one architecture, the decomposable AddSub costs a steady 10-20% more power than
a gated bank (about 15% without glitches) and saves 55-62% area. Look-ahead everywhere is the
wrong way to get that consistency, though, because it raises every unit's energy by 1.5-3x.
For a fair and efficient comparison, quote both sides at their own best architecture per target
(the segmented results above) and attribute the 500-900 MHz gap to the architecture switch.
