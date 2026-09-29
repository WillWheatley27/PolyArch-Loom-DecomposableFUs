set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/revised_fp_fus/two_level_speed/raw
file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR ${ROOT}/rtl]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017
set jobs {
  {fp_minmax_rev32_16 rtl/revised_fp_fus/fu_fp_minmax_32_16.sv fu_fp_minmax_revised_32_16}
  {fp_minmax_fixed_32 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_32.sv fu_fp_min_max_32}
  {fp_minmax_fixed_16x2 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_16x2.sv fu_fp_min_max_16x2}
}
# Optional: JOB_FILTER=<regexp> reruns only the matching jobs.
if {[info exists ::env(JOB_FILTER)]} { set jobs [lsearch -all -inline -regexp $jobs $::env(JOB_FILTER)] }
foreach j $jobs {
  lassign $j name rtl_rel top
  remove_design -all
  analyze -format sverilog ${ROOT}/${rtl_rel}
  elaborate $top
  link
  set_max_delay 0.010 -from [all_inputs] -to [all_outputs]
  compile_ultra -no_autoungroup
  catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}
  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arr 0.0
  foreach_in_collection p $paths {set arr [get_attribute $p arrival]}
  set fmax [expr {$arr > 0 ? 1.0/$arr : 0.0}]
  set out ${OUTROOT}/${name}; file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 1 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FU=${name} TOP=${top} TARGET_PERIOD_NS=0.010 ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic"
  close $fh
  echo "RESULT ${name} arrival_ns=${arr} fmax_ghz=${fmax}"
}
quit
