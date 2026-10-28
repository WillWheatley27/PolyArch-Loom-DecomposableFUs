# Full PPA rerun of every decomposable FU family, its capability tiers, and its fixed-bank
# components (plus the AddSub+MinMax side-function tiers and the FP32 -> 2xFP16 split of the
# FP min/max two-level experiment), on the normalized flow used for the original data: SAED14nm RVT TT/0.8 V/25 C,
# compile_ultra -area_high_effort_script -no_autoungroup, max-delay targets of 10 ns (100 MHz),
# 2 ns (500 MHz), 1 ns (1 GHz), 0.667 ns (1.5 GHz) and 0.5 ns (2 GHz), uniform synthetic
# activity. Run one design per dc_shell session (JOB_FILTER) so no result depends on what was
# compiled before it. Reports go to reports/rerun/raw.
# Optional: CORNERS=<list> selects the targets (default: one_ghz two_ghz, run in that order).
# Optional: NETLIST=1 also writes the gate netlist, SDF, and SDC for PrimePower.
# Optional: CLOSURE=1 retries a design that misses its target with the max-delay constraint
# tightened to 90%, 80%, then 70% of the period, keeping the first result that meets the
# real target (CLOSURE_FACTOR in result.txt; 1.0 = met on the first compile).
# A design with registers (fu_add_sub_pipe) is also clocked at the target period, with clock gating.
# Optional: STATIC_MODE=1 treats mode as a static configuration input (no timing paths from it).
# Optional: RETIME=1 lets a registered design's registers move into its logic (compile_ultra -retime,
# on the flattened design).
# Optional: POWER_OPT=1 compiles power-driven: the inputs get the stimulus's activity (every input
# but mode toggles with probability 0.5 per operation) before compile, with dynamic and total power
# optimization on.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/rerun/raw
if {[info exists ::env(OUTROOT)]} { set OUTROOT $::env(OUTROOT) }
file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR ${ROOT}/rtl]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

# name | RTL | top | optional elaboration parameters
set jobs {
  {addsub_d1 rtl/fu_add_sub_gen.sv fu_add_sub_d1}
  {addsub_d2 rtl/fu_add_sub_gen.sv fu_add_sub_d2}
  {addsub_d4 rtl/fu_add_sub_gen.sv fu_add_sub_d4}
  {addsub_d8 rtl/fu_add_sub_gen.sv fu_add_sub_d8}
  {addsub_fix_64 rtl/standalone/fu_add_sub_64.sv fu_add_sub_64}
  {addsub_fix_32x2 rtl/standalone/fu_add_sub_32x2.sv fu_add_sub_32x2}
  {addsub_fix_16x4 rtl/standalone/fu_add_sub_16x4.sv fu_add_sub_16x4}
  {addsub_fix_8x8 rtl/standalone/fu_add_sub_8x8.sv fu_add_sub_8x8}
  {addsub_la_d2 rtl/fu_add_sub_prefix.sv fu_add_sub_pd2}
  {addsub_la_d4 rtl/fu_add_sub_prefix.sv fu_add_sub_pd4}
  {addsub_la_d8 rtl/fu_add_sub_prefix.sv fu_add_sub_pd8}
  {addsub_la_fix_64 rtl/fu_add_sub_prefix.sv fu_add_sub_p64}
  {addsub_la_fix_32x2 rtl/fu_add_sub_prefix.sv fu_add_sub_p32x2}
  {addsub_la_fix_16x4 rtl/fu_add_sub_prefix.sv fu_add_sub_p16x4}
  {addsub_la_fix_8x8 rtl/fu_add_sub_prefix.sv fu_add_sub_p8x8}
  {addsub_part_d2 rtl/fu_add_sub_window_fix.sv fu_add_sub_part {EN32=1,EN16=0,EN8=0}}
  {addsub_part_d4 rtl/fu_add_sub_window_fix.sv fu_add_sub_part {EN32=1,EN16=1,EN8=0}}
  {addsub_part_d8 rtl/fu_add_sub_window_fix.sv fu_add_sub_part {EN32=1,EN16=1,EN8=1}}
  {addsub_blkinc_d2 rtl/fu_add_sub_window_fix.sv fu_add_sub_blkinc {EN32=1,EN16=0,EN8=0}}
  {addsub_blkinc_d4 rtl/fu_add_sub_window_fix.sv fu_add_sub_blkinc {EN32=1,EN16=1,EN8=0}}
  {addsub_blkinc_d8 rtl/fu_add_sub_window_fix.sv fu_add_sub_blkinc {EN32=1,EN16=1,EN8=1}}
  {addsub_pipe_d2 rtl/fu_add_sub_window_fix.sv fu_add_sub_pipe {EN32=1,EN16=0,EN8=0}}
  {addsub_pipe_d4 rtl/fu_add_sub_window_fix.sv fu_add_sub_pipe {EN32=1,EN16=1,EN8=0}}
  {addsub_pipe_d8 rtl/fu_add_sub_window_fix.sv fu_add_sub_pipe {EN32=1,EN16=1,EN8=1}}
  {addsub_segser_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,FLAT=0,EN32=1,EN16=0,EN8=0}}
  {addsub_segser_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,FLAT=0,EN32=1,EN16=1,EN8=0}}
  {addsub_segser_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,FLAT=0,EN32=1,EN16=1,EN8=1}}
  {addsub_segflat_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,FLAT=1,EN32=1,EN16=0,EN8=0}}
  {addsub_segflat_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,FLAT=1,EN32=1,EN16=1,EN8=0}}
  {addsub_segflat_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,FLAT=1,EN32=1,EN16=1,EN8=1}}
  {addsub_cselser_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,FLAT=0,EN32=1,EN16=0,EN8=0}}
  {addsub_cselser_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,FLAT=0,EN32=1,EN16=1,EN8=0}}
  {addsub_cselser_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,FLAT=0,EN32=1,EN16=1,EN8=1}}
  {addsub_csel_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,FLAT=1,EN32=1,EN16=0,EN8=0}}
  {addsub_csel_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,FLAT=1,EN32=1,EN16=1,EN8=0}}
  {addsub_csel_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,FLAT=1,EN32=1,EN16=1,EN8=1}}
  {addsub_dwcselser_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=2,FLAT=0,EN32=1,EN16=0,EN8=0}}
  {addsub_dwcselser_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=2,FLAT=0,EN32=1,EN16=1,EN8=0}}
  {addsub_dwcsel_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=2,FLAT=1,EN32=1,EN16=0,EN8=0}}
  {addsub_dwcsel_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=2,FLAT=1,EN32=1,EN16=1,EN8=0}}
  {addsub_segrep_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,REP_OP=1,EN32=1,EN16=0,EN8=0}}
  {addsub_segrep_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,REP_OP=1,EN32=1,EN16=1,EN8=0}}
  {addsub_segrep_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=0,REP_OP=1,EN32=1,EN16=1,EN8=1}}
  {addsub_cselrep_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,REP_OP=1,EN32=1,EN16=0,EN8=0}}
  {addsub_cselrep_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,REP_OP=1,EN32=1,EN16=1,EN8=0}}
  {addsub_cselrep_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=1,REP_OP=1,EN32=1,EN16=1,EN8=1}}
  {addsub_csel16rep_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=3,REP_OP=1,EN32=1,EN16=0,EN8=0}}
  {addsub_csel16rep_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=3,REP_OP=1,EN32=1,EN16=1,EN8=0}}
  {addsub_csel16rep_d8 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=3,REP_OP=1,EN32=1,EN16=1,EN8=1}}
  {addsub_dwcselrep_d2 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=2,REP_OP=1,EN32=1,EN16=0,EN8=0}}
  {addsub_dwcselrep_d4 rtl/fu_add_sub_spike.sv fu_add_sub_spike {ARCH=2,REP_OP=1,EN32=1,EN16=1,EN8=0}}
  {addsub_probe0_32x2 rtl/fu_add_sub_spike.sv fu_add_sub_spike_probe32x2 {PRIM=0}}
  {addsub_probe1_32x2 rtl/fu_add_sub_spike.sv fu_add_sub_spike_probe32x2 {PRIM=1}}
  {addsub_probe2_32x2 rtl/fu_add_sub_spike.sv fu_add_sub_spike_probe32x2 {PRIM=2}}
  {addsub_probe3_32x2 rtl/fu_add_sub_spike.sv fu_add_sub_spike_probe32x2 {PRIM=3}}
  {addsub_probe4_32x2 rtl/fu_add_sub_spike.sv fu_add_sub_spike_probe32x2 {PRIM=4}}
  {mm_seg_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=0,EN32=1,EN16=0,EN8=0}}
  {mm_seg_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=0,EN32=1,EN16=1,EN8=0}}
  {mm_seg_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=0,EN32=1,EN16=1,EN8=1}}
  {mm_csel_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=0,EN32=1,EN16=0,EN8=0}}
  {mm_csel_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=0,EN32=1,EN16=1,EN8=0}}
  {mm_csel_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=0,EN32=1,EN16=1,EN8=1}}
  {as_seg_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=0,EN32=1,EN16=0,EN8=0}}
  {as_seg_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=0,EN32=1,EN16=1,EN8=0}}
  {as_seg_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=0,EN32=1,EN16=1,EN8=1}}
  {as_csel_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=0,EN32=1,EN16=0,EN8=0}}
  {as_csel_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=0,EN32=1,EN16=1,EN8=0}}
  {as_csel_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=0,EN32=1,EN16=1,EN8=1}}
  {mm_segp_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {mm_segp_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {mm_segp_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {mm_cselp_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {mm_cselp_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {mm_cselp_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {as_segp_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {as_segp_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {as_segp_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {as_cselp_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {as_cselp_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {as_cselp_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {mm_segl_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=2,EN32=1,EN16=0,EN8=0}}
  {mm_segl_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=2,EN32=1,EN16=1,EN8=0}}
  {mm_segl_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=2,EN32=1,EN16=1,EN8=1}}
  {mm_csell_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=2,EN32=1,EN16=0,EN8=0}}
  {mm_csell_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=2,EN32=1,EN16=1,EN8=0}}
  {mm_csell_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=2,EN32=1,EN16=1,EN8=1}}
  {mm_sego_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {mm_sego_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {mm_sego_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {mm_cselo_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {mm_cselo_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {mm_cselo_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=1,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {as_sego_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {as_sego_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {as_sego_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=0,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {as_cselo_d2 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=1,EN32=1,EN16=0,EN8=0}}
  {as_cselo_d4 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=0}}
  {as_cselo_d8 rtl/fu_add_sub_mm.sv fu_add_sub_mm {ARCH=1,MINMAX=0,PIPE=1,EN32=1,EN16=1,EN8=1}}
  {minmax_m2o rtl/fu_add_sub_mm.sv fu_min_max_piped {EN32=1,EN16=0}}
  {minmax_m4o rtl/fu_add_sub_mm.sv fu_min_max_piped {EN32=1,EN16=1}}
  {minmax_m2p rtl/fu_add_sub_mm.sv fu_min_max_piped {EN32=1,EN16=0}}
  {minmax_m4p rtl/fu_add_sub_mm.sv fu_min_max_piped {EN32=1,EN16=1}}
  {minmax_m1 rtl/fu_min_max_gen.sv fu_min_max_m1}
  {minmax_m2 rtl/fu_min_max_gen.sv fu_min_max_m2}
  {minmax_m4 rtl/fu_min_max_gen.sv fu_min_max_m4}
  {minmax_fix_64 rtl/fu_min_max.sv fu_min_max}
  {minmax_fix_32x2 rtl/standalone/min_max_standalones/fu_min_max_32x2.sv fu_min_max_32x2}
  {minmax_fix_16x4 rtl/standalone/min_max_standalones/fu_min_max_16x4.sv fu_min_max_16x4}
  {cmp_c1 rtl/fu_cmp_gen.sv fu_cmp_c1}
  {cmp_c2 rtl/fu_cmp_gen.sv fu_cmp_c2}
  {cmp_c4 rtl/fu_cmp_gen.sv fu_cmp_c4}
  {cmp_c8 rtl/fu_cmp_gen.sv fu_cmp_c8}
  {cmp_fix_64 rtl/standalone/cmp_standalones/fu_cmp_64.sv fu_cmp_64}
  {cmp_fix_32x2 rtl/standalone/cmp_standalones/fu_cmp_32x2.sv fu_cmp_32x2}
  {cmp_fix_16x4 rtl/standalone/cmp_standalones/fu_cmp_16x4.sv fu_cmp_16x4}
  {cmp_fix_8x8 rtl/standalone/cmp_standalones/fu_cmp_8x8.sv fu_cmp_8x8}
  {abs_a1 rtl/fu_abs_gen.sv fu_abs_a1}
  {abs_a2 rtl/fu_abs_gen.sv fu_abs_a2}
  {abs_a3 rtl/fu_abs_gen.sv fu_abs_a3}
  {abs_fix_32x2 rtl/standalone/abs_standalones/fu_abs_32x2.sv fu_abs_32x2}
  {abs_fix_16x4 rtl/standalone/abs_standalones/fu_abs_16x4.sv fu_abs_16x4}
  {barrel_bs1 rtl/fu_barrel_shift_gen.sv fu_bshift_bs1}
  {barrel_bs2 rtl/fu_barrel_shift_gen.sv fu_bshift_bs2}
  {barrel_bs3 rtl/fu_barrel_shift_gen.sv fu_bshift_bs3}
  {barrel_fix_32x2 rtl/standalone/barrel_shift_standalones/fu_barrel_shift_32x2.sv fu_barrel_shift_32x2}
  {barrel_fix_16x4 rtl/standalone/barrel_shift_standalones/fu_barrel_shift_16x4.sv fu_barrel_shift_16x4}
  {fp_cmp_g1 rtl/fu_fp_cmp_gen.sv fu_fp_cmp_g1}
  {fp_cmp_g2 rtl/fu_fp_cmp_gen.sv fu_fp_cmp_g2}
  {fp_cmp_g3 rtl/fu_fp_cmp_gen.sv fu_fp_cmp_g3}
  {fp_cmp_fix_64 rtl/standalone/fp_cmp_standalones/fu_fp_cmp_64.sv fu_fp_cmp_64}
  {fp_cmp_fix_32x2 rtl/standalone/fp_cmp_standalones/fu_fp_cmp_32x2.sv fu_fp_cmp_32x2}
  {fp_cmp_fix_16x4 rtl/standalone/fp_cmp_standalones/fu_fp_cmp_16x4.sv fu_fp_cmp_16x4}
  {fp_minmax_m1 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m1}
  {fp_minmax_m2 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m2}
  {fp_minmax_m3 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m3}
  {fp_minmax_fix_64 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_64.sv fu_fp_min_max_64}
  {fp_minmax_fix_32x2 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_32x2.sv fu_fp_min_max_32x2}
  {fp_minmax_fix_16x4 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_16x4.sv fu_fp_min_max_16x4}
  {rounding_g1 rtl/fu_rounding_gen.sv fu_rounding_g1}
  {rounding_g2 rtl/fu_rounding_gen.sv fu_rounding_g2}
  {rounding_g3 rtl/fu_rounding_gen.sv fu_rounding_g3}
  {rounding_fix_32x2 rtl/standalone/rounding_standalones/fu_rounding_32x2.sv fu_rounding_32x2}
  {rounding_fix_16x4 rtl/standalone/rounding_standalones/fu_rounding_16x4.sv fu_rounding_16x4}
  {mult_k64 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_64.sv fu_mult_karatsuba_64}
  {mult_k64_1l rtl/fu_mult_karatsuba_64_32.sv fu_mult_karatsuba_64_1l}
  {mult_k64_32 rtl/fu_mult_karatsuba_64_32.sv fu_mult_karatsuba_64_32}
  {mult_k64_32_16 rtl/fu_mult_decomp.sv fu_mult_decomp}
  {mult_kfix_32x2 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_32x2.sv fu_mult_karatsuba_32x2}
  {mult_kfix_16x4 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_16x4.sv fu_mult_karatsuba_16x4}
  {mult_dwfix_64 rtl/standalone/mult_standalones/fu_mult_64.sv fu_mult_64}
  {mult_dwfix_32x2 rtl/standalone/mult_standalones/fu_mult_32x2.sv fu_mult_32x2}
  {mult_dwfix_16x4 rtl/standalone/mult_standalones/fu_mult_16x4.sv fu_mult_16x4}
  {addsub_minmax_d1 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d1}
  {addsub_minmax_d2 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d2}
  {addsub_minmax_d4 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d4}
  {addsub_minmax_d8 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d8}
  {fp_minmax_w32_m1 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_dec {W=32,MIN_LANE_W=32}}
  {fp_minmax_w32_m2 rtl/revised_fp_fus/fu_fp_minmax_32_16.sv fu_fp_minmax_revised_32_16}
  {fp_minmax_fix_32 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_32.sv fu_fp_min_max_32}
  {fp_minmax_fix_16x2 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_16x2.sv fu_fp_min_max_16x2}
}
set PERIOD(100_mhz) 10.000
set PERIOD(400_mhz) 2.500
set PERIOD(450_mhz) [expr {1.0 / 0.45}]
set PERIOD(500_mhz) 2.000
set PERIOD(550_mhz) [expr {1.0 / 0.55}]
set PERIOD(600_mhz) [expr {5.0 / 3.0}]
set PERIOD(700_mhz) [expr {1.0 / 0.7}]
set PERIOD(800_mhz) 1.250
set PERIOD(900_mhz) [expr {1.0 / 0.9}]
set PERIOD(one_ghz) 1.000
set PERIOD(1p5_ghz) [expr {2.0 / 3.0}]
set PERIOD(two_ghz) 0.500
set corners {one_ghz two_ghz}
if {[info exists ::env(CORNERS)]} { set corners $::env(CORNERS) }

proc compile_at {rtl_rel top params constraint} {
  global ROOT
  remove_design -all
  if {[analyze -format sverilog ${ROOT}/${rtl_rel}] == 0} { error "analyze failed: $rtl_rel" }
  if {$params eq ""} { elaborate $top } else { elaborate $top -parameters $params }
  link
  set_max_delay $constraint -from [all_inputs] -to [all_outputs]
  if {[info exists ::env(STATIC_MODE)]} { set_false_path -from [get_ports -quiet mode*] }
  set gating {}
  if {[sizeof_collection [all_registers]] > 0} {
    # Registered design: every input-to-register and register-to-output path gets the same
    # period as the input-to-output paths, and DC gates the register clocks. With no clock-tree
    # synthesis, each clock gate drives at most 16 flops, like a clock-tree leaf buffer, so the
    # wire-load model sees leaf-sized clock nets instead of one net to every flop.
    set_clock_gating_style -max_fanout 16
    create_clock -name clk -period $constraint [get_ports clk]
    set_input_delay 0 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
    set_output_delay 0 -clock clk [all_outputs]
    set gating -gate_clock
    # RETIME=1: the registers may move into the logic (the hierarchy is flattened so they can).
    if {[info exists ::env(RETIME)]} {
      ungroup -all -flatten
      lappend gating -retime
    }
  }
  if {[info exists ::env(POWER_OPT)]} {
    set_switching_activity -static_probability 0.5 -toggle_rate 0.5 -period $constraint \
      [remove_from_collection [all_inputs] [get_ports -quiet mode*]]
    set_switching_activity -static_probability 0.5 -toggle_rate 0 [get_ports -quiet mode*]
    set_dynamic_optimization true
    set_app_var compile_enable_total_power_optimization true
  }
  compile_ultra -area_high_effort_script -no_autoungroup {*}$gating
  # Worst-path arrival; for a registered design, the delay that path needs including the setup
  # time at a register endpoint.
  set arr 0.0
  foreach_in_collection p [get_timing_paths -delay_type max -max_paths 1 -nworst 1] {
    set arr [get_attribute $p arrival]
    if {$gating ne {}} { set arr [expr {$constraint - [get_attribute $p slack]}] }
  }
  return $arr
}

proc run_one {name rtl_rel top params corner} {
  global OUTROOT PERIOD
  set period $PERIOD($corner)
  set factors {1.0}
  if {[info exists ::env(CLOSURE)]} { set factors {1.0 0.9 0.8 0.7} }
  foreach f $factors {
    set arr [compile_at $rtl_rel $top $params [expr {$period * $f}]]
    if {$arr <= $period + 1e-6} { break }
  }
  catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}
  set fmax [expr {$arr > 0 ? 1.0/$arr : 0.0}]
  set out ${OUTROOT}/${name}/${corner}
  file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 1 > ${out}/report_timing.rpt
  if {[info exists ::env(NETLIST)]} {
    change_names -rules verilog -hierarchy
    write -format verilog -hierarchy -output ${out}/netlist.v
    write_sdf ${out}/netlist.sdf
    write_sdc ${out}/netlist.sdc
  }
  set fh [open ${out}/result.txt w]
  # TOP is the elaborated design name (parameterized tops get a suffixed name).
  puts $fh "FU=${name} TOP=[get_object_name [current_design]] TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} CLOSURE_FACTOR=${f} ACTIVITY_SOURCE=uniform_synthetic"
  close $fh
  echo "RESULT ${name} ${corner} arrival_ns=${arr} fmax_ghz=${fmax} closure_factor=${f}"
}

# Optional: JOB_FILTER=<regexp> selects the jobs to run.
if {[info exists ::env(JOB_FILTER)]} { set jobs [lsearch -all -inline -regexp $jobs $::env(JOB_FILTER)] }
foreach j $jobs {
  lassign $j name rtl top params
  foreach corner $corners { run_one $name $rtl $top $params $corner }
}
quit
