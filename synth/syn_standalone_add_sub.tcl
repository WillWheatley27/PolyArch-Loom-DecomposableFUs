# SAED14nm synthesis for the fixed-lane AddSub bank baselines.
# Designs are standalone packed-lane units: no runtime mode and no cross-lane carry.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB     saed14rvt_base_tt0p8v25c.db
set ROOT    /edata1/will/Decomposable_FU
set OUT_DIR ${ROOT}/synth/standalone

file mkdir $OUT_DIR
set search_path    [concat $search_path $LIB_DIR]
set link_library   [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

proc run_corner {rtl design tag max_delay area_effort out_dir} {
  remove_design -all
  if {[analyze -format sverilog $rtl] == 0} { error "analyze failed: $rtl" }
  elaborate $design
  link
  set_max_delay $max_delay -from [all_inputs] -to [all_outputs]
  if {$area_effort} {
    compile_ultra -area_high_effort_script -no_autoungroup
  } else {
    compile_ultra -no_autoungroup
  }

  # Keep switching assumptions identical across all standalone baselines.
  catch { set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs] }
  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arr_ns 0.0
  foreach_in_collection p $paths { set arr_ns [get_attribute $p arrival] }
  set fmax_ghz [expr {$arr_ns > 0 ? 1.0 / $arr_ns : 0.0}]

  report_area  > ${out_dir}/report_area_${design}_${tag}.rpt
  report_power -analysis_effort low > ${out_dir}/report_power_${design}_${tag}.rpt
  report_timing -delay_type max -nworst 1 > ${out_dir}/report_timing_${design}_${tag}.rpt
  echo "RESULT ${design} ${tag} fmax_ghz=${fmax_ghz} critical_path_ns=${arr_ns}"
}

run_corner ${ROOT}/rtl/standalone/fu_add_sub_32x2.sv fu_add_sub_32x2 speed 0.010 0 $OUT_DIR
run_corner ${ROOT}/rtl/standalone/fu_add_sub_32x2.sv fu_add_sub_32x2 area  0.360 1 $OUT_DIR
run_corner ${ROOT}/rtl/standalone/fu_add_sub_16x4.sv fu_add_sub_16x4 speed 0.010 0 $OUT_DIR
run_corner ${ROOT}/rtl/standalone/fu_add_sub_16x4.sv fu_add_sub_16x4 area  0.360 1 $OUT_DIR
run_corner ${ROOT}/rtl/standalone/fu_add_sub_8x8.sv  fu_add_sub_8x8  speed 0.010 0 $OUT_DIR
run_corner ${ROOT}/rtl/standalone/fu_add_sub_8x8.sv  fu_add_sub_8x8  area  0.360 1 $OUT_DIR
quit
