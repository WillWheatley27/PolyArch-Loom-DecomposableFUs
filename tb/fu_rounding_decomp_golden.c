// fu_rounding_decomp_golden.c -- DPI-C hardware/libm golden for tb_fu_rounding_decomp.
// Round-to-integral via C library functions, selected by round_mode:
//   000 floor, 001 ceil, 010 trunc, 011 round (ties away), 100 rint (ties to even),
//   other -> trunc. fp64 -> double, fp32 -> float, fp16 -> x86 F16C (result is an integer
//   exactly representable in fp16, so the round-trip is exact). Compile with -mf16c.
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

static double round64(double x, int rm) {
  switch (rm) {
    case 0: return floor(x);
    case 1: return ceil(x);
    case 3: return round(x);   // ties away from zero
    case 4: return rint(x);    // ties to even (default FP env)
    default: return trunc(x);  // 010 and reserved
  }
}
static float round32(float x, int rm) {
  switch (rm) {
    case 0: return floorf(x);
    case 1: return ceilf(x);
    case 3: return roundf(x);
    case 4: return rintf(x);
    default: return truncf(x);
  }
}

uint64_t g_fp64_round(uint64_t a, int rm) {
  double x; memcpy(&x, &a, 8);
  double r = round64(x, rm);
  uint64_t o; memcpy(&o, &r, 8); return o;
}
uint32_t g_fp32_round(uint32_t a, int rm) {
  float x; memcpy(&x, &a, 4);
  float r = round32(x, rm);
  uint32_t o; memcpy(&o, &r, 4); return o;
}
uint32_t g_fp16_round(uint32_t a, int rm) {
  float x = _cvtsh_ss((unsigned short)(a & 0xFFFFu));
  float r = round32(x, rm);
  return (uint32_t)(unsigned short)_cvtss_sh(r, 0);
}

#ifdef __cplusplus
}
#endif
