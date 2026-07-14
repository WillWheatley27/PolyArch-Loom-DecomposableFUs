// fu_fp_add_sub_decomp_golden.c -- DPI-C hardware-FP golden for tb_fu_fp_add_sub_decomp.
// Bit-exact IEEE-754 add/sub references using native hardware:
//   fp64 -> C double, fp32 -> C float, fp16 -> x86 F16C conversion intrinsics.
// Fully independent of the DUT (no hand-written rounding). Compile with -mf16c.
#include <stdint.h>
#include <string.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

// fp64: bits -> double, add/sub, -> bits.
uint64_t g_fp64_add(uint64_t a, uint64_t b, int sub) {
  double x, y;
  memcpy(&x, &a, 8);
  memcpy(&y, &b, 8);
  if (sub) y = -y;
  double r = x + y;
  uint64_t o;
  memcpy(&o, &r, 8);
  return o;
}

// fp32: low 32 bits -> float, add/sub, -> bits (in low 32).
uint32_t g_fp32_add(uint32_t a, uint32_t b, int sub) {
  float x, y;
  memcpy(&x, &a, 4);
  memcpy(&y, &b, 4);
  if (sub) y = -y;
  float r = x + y;
  uint32_t o;
  memcpy(&o, &r, 4);
  return o;
}

// fp16: low 16 bits -> float (F16C), add/sub in float, round back to fp16 (F16C, RNE).
// float has 24-bit significand >= 2*11+2, so fp16-add-via-float rounds correctly (no
// double-rounding error). Returns the 16-bit result in the low bits.
uint32_t g_fp16_add(uint32_t a, uint32_t b, int sub) {
  float x = _cvtsh_ss((unsigned short)(a & 0xFFFFu));
  float y = _cvtsh_ss((unsigned short)(b & 0xFFFFu));
  if (sub) y = -y;
  return (uint32_t)(unsigned short)_cvtss_sh(x + y, 0 /* round-to-nearest-even */);
}

#ifdef __cplusplus
}
#endif
