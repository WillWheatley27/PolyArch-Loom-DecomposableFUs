# Normalized SAED14nm/DC synthesis for the revised FP compare/min/max tiers.
# Each tier is a separate top-level wrapper so unsupported formats are removed
# at elaboration.  Reports are written below reports/revised_fp_fus/raw.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB     saed14rvt_base_tt0p8v25c.db
set ROOT    /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/revised_fp_fus/raw

file mkdir $OUTROOT
set search_path    [concat $search_path $LIB_DIR]
set link_library   [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

set jobs {
  {fp_cmp_rev64       rtl/revised_fp_fus/fu_fp_cmp_revised_shared.sv       fu_fp_cmp_revised_shared64}
  {fp_cmp_rev64_32    rtl/revised_fp_fus/fu_fp_cmp_revised_shared.sv       fu_fp_cmp_revised_shared64_32}
  {fp_cmp_rev64_32_16 rtl/revised_fp_fus/fu_fp_cmp_revised_shared.sv       fu_fp_cmp_revised_shared64_32_16}
  {fp_minmax_rev64       rtl/revised_fp_fus/fu_fp_minmax_revised_shared.sv fu_fp_minmax_revised_shared64}
  {fp_minmax_rev64_32    rtl/revised_fp_fus/fu_fp_minmax_revised_shared.sv fu_fp_minmax_revised_shared64_32}
  {fp_minmax_rev64_32_16 rtl/revised_fp_fus/fu_fp_minmax_revised_shared.sv fu_fp_minmax_revised_shared64_32_16}
}

proc run_one {name rtl_rel top corner period area_effort} {
  global ROOT OUTROOT
  remove_design -all
  set rtl ${ROOT}/${rtl_rel}
  if {[analyze -format sverilog $rtl] == 0} { error "analyze failed: $rtl" }
  elaborate $top
  link
  set_max_delay $period -from [all_inputs] -to [all_outputs]
  if {$area_effort} {
    compile_ultra -area_high_effort_script -no_autoungroup
  } else {
    compile_ultra -no_autoungroup
  }
  catch { set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs] }
  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arr_ns 0.0
  foreach_in_collection p $paths { set arr_ns [get_attribute $p arrival] }
  set fmax_ghz [expr {$arr_ns > 0 ? 1.0 / $arr_ns : 0.0}]
  set out ${OUTROOT}/${name}/${corner}
  file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 1 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FU=${name} TOP=${top} TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arr_ns} FMAX_GHZ=${fmax_ghz} ACTIVITY_SOURCE=uniform_synthetic"
  close $fh
  echo "RESULT ${name} ${corner} arrival_ns=${arr_ns} fmax_ghz=${fmax_ghz}"
}

foreach job $jobs {
  lassign $job name rtl top
  run_one $name $rtl $top one_ghz 1.000 1
  run_one $name $rtl $top two_ghz 0.500 1
}
quit
