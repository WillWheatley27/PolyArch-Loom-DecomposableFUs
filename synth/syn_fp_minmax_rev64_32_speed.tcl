set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUT ${ROOT}/reports/revised_fp_fus/two_level_speed/raw/fp_minmax_rev64_32
file mkdir $OUT
set search_path [concat $search_path $LIB_DIR]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017
analyze -format sverilog ${ROOT}/rtl/revised_fp_fus/fu_fp_minmax_revised_shared.sv
elaborate fu_fp_minmax_revised_shared64_32
link
set_max_delay 0.010 -from [all_inputs] -to [all_outputs]
compile_ultra -no_autoungroup
catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set arr 0.0
foreach_in_collection p $paths {set arr [get_attribute $p arrival]}
set fmax [expr {$arr > 0 ? 1.0/$arr : 0.0}]
report_area > ${OUT}/report_area.rpt
report_power -analysis_effort low > ${OUT}/report_power.rpt
report_timing -delay_type max -nworst 1 > ${OUT}/report_timing.rpt
set fh [open ${OUT}/result.txt w]
puts $fh "FU=fp_minmax_rev64_32 TOP=fu_fp_minmax_revised_shared64_32 TARGET_PERIOD_NS=0.010 ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic"
close $fh
echo "RESULT fp_minmax_rev64_32 arrival_ns=${arr} fmax_ghz=${fmax}"
quit
