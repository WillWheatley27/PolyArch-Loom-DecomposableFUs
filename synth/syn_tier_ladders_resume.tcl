set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/tier_ladders/raw
set search_path [concat $search_path $LIB_DIR]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017
set jobs {
  {rounding g2 FP64_FP32x2 rtl/fu_rounding_gen.sv fu_rounding_g2}
  {rounding g3 FP64_FP32x2_FP16x4 rtl/fu_rounding_gen.sv fu_rounding_g3}
  {fp_cmp g1 FP64 rtl/fu_fp_cmp_gen.sv fu_fp_cmp_g1}
  {fp_cmp g2 FP64_FP32x2 rtl/fu_fp_cmp_gen.sv fu_fp_cmp_g2}
  {fp_cmp g3 FP64_FP32x2_FP16x4 rtl/fu_fp_cmp_gen.sv fu_fp_cmp_g3}
  {fp_minmax m1 FP64 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m1}
  {fp_minmax m2 FP64_FP32x2 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m2}
  {fp_minmax m3 FP64_FP32x2_FP16x4 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m3}
}
proc run_one {family tier cap rtl_rel top corner period} {
  global ROOT OUTROOT
  remove_design -all
  analyze -format sverilog ${ROOT}/${rtl_rel}
  elaborate $top
  link
  set_max_delay $period -from [all_inputs] -to [all_outputs]
  compile_ultra -area_high_effort_script -no_autoungroup
  catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}
  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arr 0.0
  foreach_in_collection p $paths {set arr [get_attribute $p arrival]}
  set fmax [expr {$arr > 0 ? 1.0/$arr : 0.0}]
  set out ${OUTROOT}/${family}/${tier}/${corner}; file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 1 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FAMILY=${family} TIER=${tier} CAPABILITY=${cap} TOP=${top} TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic"
  close $fh
  echo "RESULT ${family} ${tier} ${corner} arrival_ns=${arr} fmax_ghz=${fmax}"
}
foreach j $jobs {
  lassign $j family tier cap rtl top
  run_one $family $tier $cap $rtl $top one_ghz 1.000
  run_one $family $tier $cap $rtl $top two_ghz 0.500
}
quit
