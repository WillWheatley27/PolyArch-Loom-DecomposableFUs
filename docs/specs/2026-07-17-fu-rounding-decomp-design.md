# fu_rounding_decomp — Design Spec

**Date:** 2026-07-17
**Status:** Approved (design)
**Share group:** 17 (`math.floor`, `math.ceil`, `math.trunc`, `math.round`, `math.roundeven`) —
⚪ "decomposable but low value" in `DECOMPOSABILITY_ANALYSIS.md` (feasible, marginal area win).
The last genuinely-interesting lane-separable FP op.
**Deliverable:** standalone RTL + self-checking testbench (DPI-C golden)

## 1. Context & decomposability

Round-to-integral is a **unary** FP op: it rounds a floating-point value to an integral
floating-point value per a rounding direction. Its datapath is exponent/mantissa **mask +
conditional increment** — lane-separable and combinational, no per-format constant tables → it
decomposes. It is low-value only because the FU is cheap (mostly masks), not because it can't
decompose. This is the first **unary** FU in the family (1-input handshake).

`decomposability = [32,16]` → 1×fp64 / 2×fp32 / 4×fp16, all lanes rounded the same direction.

## 2. Semantics (MLIR math dialect)

`round_mode` (global): `000` floor (→−∞), `001` ceil (→+∞), `010` trunc (→0), `011` round
(nearest, **ties away from zero**), `100` roundeven (nearest, **ties to even**); other codes →
trunc. Result is an integral FP value. NaN→NaN, ±Inf→±Inf, ±0→±0 (all returned unchanged);
already-integral values returned unchanged; sign preserved (e.g. `ceil(−0.3) = −0`,
`floor(−0.3) = −1`).

## 3. Interface (unary)

```systemverilog
module fu_rounding_decomp (
  input  logic        clk, rst_n,      // held; combinational core (lint-waived unused)
  input  logic [1:0]  mode,            // 00=1×fp64, 01=2×fp32, 10=4×fp16, 11=rsvd→1×fp64
  input  logic [2:0]  round_mode,      // global: 000 floor,001 ceil,010 trunc,011 round,100 roundeven
  input  logic [63:0] in_data_0, input logic in_valid_0, output logic in_ready_0,
  output logic [63:0] out_data, output logic out_valid, input logic out_ready
);
```

Single operand — 1-input handshake: `out_valid = in_valid_0`, `in_ready_0 = out_ready & out_valid`.
Little-endian lanes. `round_mode` is global (the rounding direction is per-instruction).

## 4. Datapath (combinational)

Per lane `round_lane(x, round_mode, EXP_W, MAN_W)`:
- Decode `s`, `exp`, `mant`; unbiased `E = exp − bias` (subnormal ⇒ `1 − bias`, implicit 0).
- **Return `x` unchanged** if NaN/Inf (`exp` all-ones), ±0, or already integral (`E ≥ MAN_W`).
- Significand `sig = {implicit, mant}`; number of fractional bits `F = MAN_W − E`.
- **`0 ≤ E < MAN_W`** (has integer + fractional parts): guard `= sig[F−1]` (the 0.5 bit),
  sticky `= OR(sig[F−2:0])`, int_lsb `= sig[F]`. Clear the low `F` bits (`int_sig`), decide the
  increment, `new_sig = int_sig + (inc << F)`; a carry into bit `MAN_W+1` bumps the exponent.
- **`E < 0`** (`|x| < 1`, integer part 0): guard is the 0.5 bit (implicit when `E = −1`, else 0),
  sticky = 1 (nonzero); result is `±0` or `±1.0` by the increment.
- **Increment decision** (`inc`):

  ```
  floor    : s & (guard | sticky)      // negative + any fraction → away from 0
  ceil     : ~s & (guard | sticky)     // positive + any fraction → away from 0
  trunc    : 0
  round    : guard                     // nearest, ties away
  roundeven: guard & (sticky | int_lsb) // nearest, ties to even
  ```

Top: per-mode lane calls + mode mux (`00`/reserved `11` → fp64). Functional decomposition; a
physically-shared segmented rounding network is the synthesis/area objective.

## 5. Handshake & latency

Unary, combinational, latency 0.

## 6. Verification — DPI-C golden

`tb/fu_rounding_decomp_golden.c`: C `floor`/`ceil`/`trunc`/`round`/`rint` on `double`/`float`/F16C,
selected by `round_mode` (reserved → trunc). Returns the result bits. NaN-lenient compare;
everything else (incl signed zero) bit-exact. Directed: each mode on `±2.5`, `±3.5` (ties even),
`±0.5`, `±0.3`, integral values, large integral, ±Inf, NaN, ±0, subnormal, max; per-lane
independence. ~20,000 uniform + ~20,000 small-exponent random over `(mode, round_mode, a)`.
`$fatal(1)` on mismatch. `run.sh` compiles the golden with `-mf16c`.

## 7. Out of scope / follow-ups

- **Physical shared segmented rounding network** (area objective); **area validation**;
  **pipelining**; **generator/share-group integration**; **generalization**.
