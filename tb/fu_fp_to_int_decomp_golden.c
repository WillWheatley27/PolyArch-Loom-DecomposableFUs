// fu_fp_to_int_decomp_golden.c -- DPI-C golden for tb_fu_fp_to_int_decomp.
// Saturating, round-toward-zero float->int conversion (defined hardware behavior):
//   round toward zero (trunc), out-of-range -> clamp to int min/max, NaN -> 0.
//   fp64->int64 (double), fp32->int32 (float), fp16->int16 (F16C->float). Compile with -mf16c.
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t g_fp64_f2i(uint64_t a, int is_signed) {
  double x; memcpy(&x, &a, 8);
  if (isnan(x)) return 0;
  double t = trunc(x);
  if (is_signed) {
    if (t >=  9223372036854775808.0) return (uint64_t)INT64_MAX;   //  2^63
    if (t <  -9223372036854775808.0) return (uint64_t)INT64_MIN;   // -2^63
    return (uint64_t)(int64_t)t;
  } else {
    if (t < 0.0)                      return 0;
    if (t >= 18446744073709551616.0)  return UINT64_MAX;           //  2^64
    return (uint64_t)t;
  }
}

uint32_t g_fp32_f2i(uint32_t a, int is_signed) {
  float x; memcpy(&x, &a, 4);
  if (isnan(x)) return 0;
  float t = truncf(x);
  if (is_signed) {
    if (t >=  2147483648.0f) return (uint32_t)INT32_MAX;   //  2^31
    if (t <  -2147483648.0f) return (uint32_t)INT32_MIN;
    return (uint32_t)(int32_t)t;
  } else {
    if (t < 0.0f)            return 0;
    if (t >= 4294967296.0f)  return UINT32_MAX;            //  2^32
    return (uint32_t)t;
  }
}

uint32_t g_fp16_f2i(uint32_t a, int is_signed) {
  float x = _cvtsh_ss((unsigned short)(a & 0xFFFFu));
  if (isnan(x)) return 0;
  float t = truncf(x);
  if (is_signed) {
    if (t >=  32768.0f) return (uint32_t)(uint16_t)(int16_t)32767;
    if (t <  -32768.0f) return (uint32_t)(uint16_t)(int16_t)(-32768);
    return (uint32_t)(uint16_t)(int16_t)t;
  } else {
    if (t < 0.0f)       return 0;
    if (t >= 65536.0f)  return 0xFFFFu;
    return (uint32_t)(uint16_t)t;
  }
}

#ifdef __cplusplus
}
#endif
