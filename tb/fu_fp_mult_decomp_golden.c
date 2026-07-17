// fu_fp_mult_decomp_golden.c -- DPI-C hardware-FP golden for tb_fu_fp_mult_decomp.
// Bit-exact IEEE-754 multiply references using native hardware:
//   fp64 -> C double, fp32 -> C float, fp16 -> x86 F16C conversion intrinsics.
// Fully independent of the DUT (no hand-written rounding). Compile with -mf16c.
// (fp16 product has <=22 significand bits, exact in float; fp32 exact in double.)
#include <stdint.h>
#include <string.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t g_fp64_mul(uint64_t a, uint64_t b) {
  double x, y;
  memcpy(&x, &a, 8);
  memcpy(&y, &b, 8);
  double r = x * y;
  uint64_t o;
  memcpy(&o, &r, 8);
  return o;
}

uint32_t g_fp32_mul(uint32_t a, uint32_t b) {
  float x, y;
  memcpy(&x, &a, 4);
  memcpy(&y, &b, 4);
  float r = x * y;
  uint32_t o;
  memcpy(&o, &r, 4);
  return o;
}

// fp16 -> float (F16C), multiply in float (exact for fp16 operands), round to fp16 (F16C, RNE).
uint32_t g_fp16_mul(uint32_t a, uint32_t b) {
  float x = _cvtsh_ss((unsigned short)(a & 0xFFFFu));
  float y = _cvtsh_ss((unsigned short)(b & 0xFFFFu));
  return (uint32_t)(unsigned short)_cvtss_sh(x * y, 0 /* round-to-nearest-even */);
}

#ifdef __cplusplus
}
#endif
