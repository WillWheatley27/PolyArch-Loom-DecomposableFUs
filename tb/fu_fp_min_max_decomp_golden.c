// fu_fp_min_max_decomp_golden.c -- DPI-C hardware-FP golden for tb_fu_fp_min_max_decomp.
// Implements IEEE-754-2019 minimum/maximum (arith.minimumf/maximumf):
//   * NaN if either operand is NaN (canonical qNaN);
//   * -0.0 < +0.0 (sign-aware zeros);
//   * otherwise numeric min/max via hardware compare.
// Returns exactly one input's bit pattern (no rounding). Independent of the DUT.
// fp64 -> double, fp32 -> float, fp16 -> x86 F16C. Compile with -mf16c.
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t g_fp64_minmax(uint64_t a, uint64_t b, int is_max) {
  double fa, fb;
  memcpy(&fa, &a, 8);
  memcpy(&fb, &b, 8);
  if (isnan(fa) || isnan(fb)) return 0x7FF8000000000000ULL;   // qNaN
  if (fa == fb) {
    if (fa == 0.0) return is_max ? ((a >> 63) == 0 ? a : b)   // prefer +0
                                 : ((a >> 63) != 0 ? a : b);  // prefer -0
    return a;                                                 // equal nonzero -> identical bits
  }
  int agt = fa > fb;
  return is_max ? (agt ? a : b) : (agt ? b : a);
}

uint32_t g_fp32_minmax(uint32_t a, uint32_t b, int is_max) {
  float fa, fb;
  memcpy(&fa, &a, 4);
  memcpy(&fb, &b, 4);
  if (isnan(fa) || isnan(fb)) return 0x7FC00000u;
  if (fa == fb) {
    if (fa == 0.0f) return is_max ? ((a >> 31) == 0 ? a : b)
                                  : ((a >> 31) != 0 ? a : b);
    return a;
  }
  int agt = fa > fb;
  return is_max ? (agt ? a : b) : (agt ? b : a);
}

uint32_t g_fp16_minmax(uint32_t a, uint32_t b, int is_max) {
  uint16_t a16 = (uint16_t)(a & 0xFFFFu), b16 = (uint16_t)(b & 0xFFFFu);
  float fa = _cvtsh_ss(a16), fb = _cvtsh_ss(b16);
  if (isnan(fa) || isnan(fb)) return 0x7E00u;
  if (fa == fb) {
    if (fa == 0.0f) return (uint32_t)(is_max ? ((a16 >> 15) == 0 ? a16 : b16)
                                             : ((a16 >> 15) != 0 ? a16 : b16));
    return (uint32_t)a16;
  }
  int agt = fa > fb;
  return (uint32_t)(is_max ? (agt ? a16 : b16) : (agt ? b16 : a16));
}

#ifdef __cplusplus
}
#endif
