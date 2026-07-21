// fu_fp_cmp_decomp_golden.c -- DPI-C golden for tb_fu_fp_cmp_decomp.
// IEEE ordered/unordered float compare (arith.cmpf): evaluate the 16 MLIR predicates using C's
// NaN-aware relational operators + isnan (which give -0==+0 and NaN unordered). Decode each
// format to double (fp32/fp16 exact; fp16 via x86 F16C). Returns 0/1. Compile with -mf16c.
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <immintrin.h>

#ifdef __cplusplus
extern "C" {
#endif

static int cmpf_pred(double a, double b, int pred) {
  int uno = (isnan(a) || isnan(b));
  switch (pred) {
    case 0:  return 0;                    // false
    case 1:  return !uno && (a == b);     // OEQ
    case 2:  return !uno && (a >  b);     // OGT
    case 3:  return !uno && (a >= b);     // OGE
    case 4:  return !uno && (a <  b);     // OLT
    case 5:  return !uno && (a <= b);     // OLE
    case 6:  return !uno && (a != b);     // ONE
    case 7:  return !uno;                 // ORD
    case 8:  return  uno || (a == b);     // UEQ
    case 9:  return  uno || (a >  b);     // UGT
    case 10: return  uno || (a >= b);     // UGE
    case 11: return  uno || (a <  b);     // ULT
    case 12: return  uno || (a <= b);     // ULE
    case 13: return  uno || (a != b);     // UNE
    case 14: return  uno;                 // UNO
    default: return 1;                    // 15 = true
  }
}

int g_fp64_cmpf(uint64_t a, uint64_t b, int pred) {
  double x, y; memcpy(&x, &a, 8); memcpy(&y, &b, 8);
  return cmpf_pred(x, y, pred);
}
int g_fp32_cmpf(uint32_t a, uint32_t b, int pred) {
  float x, y; memcpy(&x, &a, 4); memcpy(&y, &b, 4);
  return cmpf_pred((double)x, (double)y, pred);
}
int g_fp16_cmpf(uint32_t a, uint32_t b, int pred) {
  float x = _cvtsh_ss((unsigned short)(a & 0xFFFFu));
  float y = _cvtsh_ss((unsigned short)(b & 0xFFFFu));
  return cmpf_pred((double)x, (double)y, pred);
}

#ifdef __cplusplus
}
#endif
