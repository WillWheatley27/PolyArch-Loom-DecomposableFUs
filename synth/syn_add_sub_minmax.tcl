# SAED14nm synthesis for the combined decomposable AddSub/Integer-MinMax FU.
# This is a side-function experiment: the shared segmented AddSub chain is
# reused for A-B comparison, while the Min/Max selection logic is added around
# it. Results are compared with separate decomposable AddSub + MinMax units.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/addsub_minmax
file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR ${ROOT}/rtl]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

proc run_one {tag period} {
  global ROOT OUTROOT
  remove_design -all
  analyze -format sverilog ${ROOT}/rtl/fu_add_sub_minmax_gen.sv
  elaborate fu_add_sub_minmax_d4
  link
  set_max_delay $period -from [all_inputs] -to [all_outputs]
  compile_ultra -area_high_effort_script -no_autoungroup
  catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}
  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arr 0.0
  foreach_in_collection p $paths {set arr [get_attribute $p arrival]}
  set fmax [expr {$arr > 0 ? 1.0/$arr : 0.0}]
  set out ${OUTROOT}/${tag}
  file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 1 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FU=addsub_minmax_d4 TOP=fu_add_sub_minmax_d4 TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic"
  close $fh
  echo "RESULT addsub_minmax_d4 ${tag} period_ns=${period} arrival_ns=${arr} fmax_ghz=${fmax}"
}
run_one one_ghz 1.000
run_one feasible 0.625
quit
