# Controlled SAED14nm tier study for integer Min/Max as an AddSub side function.
# Every combined, separate-decomposable, and fixed-MinMax component is compiled
# in this one flow at 1 GHz and 2 GHz.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/addsub_minmax_tiers

file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR ${ROOT}/rtl]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

# name | kind | tier | RTL | top
set jobs {
  {combined_d1 combined 64 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d1}
  {combined_d2 combined 64_32 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d2}
  {combined_d4 combined 64_32_16 rtl/fu_add_sub_minmax_gen.sv fu_add_sub_minmax_d4}
  {addsub_d1 addsub_decomposable 64 rtl/fu_add_sub_gen.sv fu_add_sub_d1}
  {addsub_d2 addsub_decomposable 64_32 rtl/fu_add_sub_gen.sv fu_add_sub_d2}
  {addsub_d4 addsub_decomposable 64_32_16 rtl/fu_add_sub_gen.sv fu_add_sub_d4}
  {minmax_m1 minmax_decomposable 64 rtl/fu_min_max_gen.sv fu_min_max_m1}
  {minmax_m2 minmax_decomposable 64_32 rtl/fu_min_max_gen.sv fu_min_max_m2}
  {minmax_m4 minmax_decomposable 64_32_16 rtl/fu_min_max_gen.sv fu_min_max_m4}
  {minmax_fixed_64 minmax_fixed 64 rtl/fu_min_max.sv fu_min_max}
  {minmax_fixed_32x2 minmax_fixed 32x2 rtl/standalone/min_max_standalones/fu_min_max_32x2.sv fu_min_max_32x2}
  {minmax_fixed_16x4 minmax_fixed 16x4 rtl/standalone/min_max_standalones/fu_min_max_16x4.sv fu_min_max_16x4}
}

proc run_one {name kind tier rtl_rel top corner period outroot} {
  global ROOT
  remove_design -all
  set rtl ${ROOT}/${rtl_rel}
  if {[analyze -format sverilog $rtl] == 0} {error "analyze failed: $rtl"}
  elaborate $top
  link
  set_max_delay $period -from [all_inputs] -to [all_outputs]
  compile_ultra -area_high_effort_script -no_autoungroup
  catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}

  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arrival 0.0
  foreach_in_collection path $paths {set arrival [get_attribute $path arrival]}
  set fmax [expr {$arrival > 0 ? 1.0/$arrival : 0.0}]
  set out ${outroot}/${corner}/${name}
  file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 10 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FU=AddSub_MinMax NAME=${name} KIND=${kind} TIER=${tier} TOP=${top} CORNER=${corner} TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arrival} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic PVT=tt0p8v25c LIBRARY=saed14rvt_base_tt0p8v25c.db"
  close $fh
  echo "RESULT ${corner} ${name} arrival_ns=${arrival} fmax_ghz=${fmax}"
}

foreach job $jobs {
  lassign $job name kind tier rtl top
  run_one $name $kind $tier $rtl $top one_ghz 1.000 $OUTROOT
  run_one $name $kind $tier $rtl $top two_ghz 0.500 $OUTROOT
}
quit
