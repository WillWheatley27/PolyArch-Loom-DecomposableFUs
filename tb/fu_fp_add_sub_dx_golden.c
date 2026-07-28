// fu_fp_add_sub_dx_golden.c -- DPI-C hardware-FP golden for tb_fu_fp_add_sub_dx.
// Bit-exact IEEE-754 add/sub references using native hardware: fp64 -> C double, fp32 -> C float.
// (No fp16 in the 64/32-only family, so no F16C needed.) Independent of the DUT.
#include <stdint.h>
#include <string.h>

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

#ifdef __cplusplus
}
#endif
