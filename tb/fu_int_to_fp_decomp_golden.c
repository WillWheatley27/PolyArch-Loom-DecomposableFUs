// fu_int_to_fp_decomp_golden.c -- DPI-C golden for tb_fu_int_to_fp_decomp.
// Trusted C integer->float conversions (round-to-nearest-even), selected by is_signed:
//   fp64: (double)(int64_t/uint64_t)   fp32: (float)(int32_t/uint32_t)
//   fp16: (float)(int16_t/uint16_t) then x86 F16C to fp16 (int16 is exact in float, so this is
//         a single RNE rounding; round-overflow -> +Inf). Compile with -mf16c.
#include <stdint.h>
#include <string.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t g_fp64_i2f(uint64_t a, int is_signed) {
  double r = is_signed ? (double)(int64_t)a : (double)(uint64_t)a;
  uint64_t o; memcpy(&o, &r, 8); return o;
}
uint32_t g_fp32_i2f(uint32_t a, int is_signed) {
  float r = is_signed ? (float)(int32_t)a : (float)(uint32_t)a;
  uint32_t o; memcpy(&o, &r, 4); return o;
}
uint32_t g_fp16_i2f(uint32_t a, int is_signed) {
  int32_t v = is_signed ? (int32_t)(int16_t)(a & 0xFFFFu)
                        : (int32_t)(uint16_t)(a & 0xFFFFu);
  float r = (float)v;
  return (uint32_t)(unsigned short)_cvtss_sh(r, 0);
}

#ifdef __cplusplus
}
#endif
