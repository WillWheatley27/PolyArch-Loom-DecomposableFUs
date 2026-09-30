# FP min/max two-level decomposition experiment: FP64 -> 2xFP32 versus FP32 -> 2xFP16.
# Both decomposable units are the same sliced core (rtl/fu_fp_min_max_gen.sv) with a 1-bit
# mode port, at W=64 and W=32; each is compared with the fixed bank covering the same formats.
# Fixed-frequency corners (1.000 ns, 0.500 ns) use the normalized area-recovery flow; the
# optional maxspeed corner (0.010 ns) uses the timing-driven stress flow.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/fp_minmax_two_level/raw/canonical
# Optional: OUTROOT=<dir> redirects reports (repeatability trials).
if {[info exists ::env(OUTROOT)]} { set OUTROOT $::env(OUTROOT) }
file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR ${ROOT}/rtl]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

# name | RTL | top | optional elaboration parameters
# hand_* are controls: the same sliced core with no split (FP64-only, FP32-only).
set jobs {
  {dec_64_32 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m2}
  {fix_64 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_64.sv fu_fp_min_max_64}
  {fix_32x2 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_32x2.sv fu_fp_min_max_32x2}
  {dec_32_16 rtl/revised_fp_fus/fu_fp_minmax_32_16.sv fu_fp_minmax_revised_32_16}
  {fix_32 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_32.sv fu_fp_min_max_32}
  {fix_16x2 rtl/standalone/fp_min_max_standalones/fu_fp_min_max_16x2.sv fu_fp_min_max_16x2}
  {hand_64 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_m1}
  {hand_32 rtl/fu_fp_min_max_gen.sv fu_fp_min_max_dec {W=32,MIN_LANE_W=32}}
}
# Optional: CORNERS=<list> (default one_ghz two_ghz; maxspeed adds the stress corner).
set corners {one_ghz two_ghz}
if {[info exists ::env(CORNERS)]} { set corners $::env(CORNERS) }
set PERIOD(one_ghz) 1.000
set PERIOD(two_ghz) 0.500
set PERIOD(maxspeed) 0.010

proc run_one {name rtl_rel top params corner} {
  global ROOT OUTROOT PERIOD
  set period $PERIOD($corner)
  remove_design -all
  if {[analyze -format sverilog ${ROOT}/${rtl_rel}] == 0} { error "analyze failed: $rtl_rel" }
  if {$params eq ""} { elaborate $top } else { elaborate $top -parameters $params }
  link
  set_max_delay $period -from [all_inputs] -to [all_outputs]
  if {$corner eq "maxspeed"} {
    compile_ultra -no_autoungroup
  } else {
    compile_ultra -area_high_effort_script -no_autoungroup
  }
  catch {set_switching_activity -static_probability 0.5 -toggle_rate 0.2 -period 1.0 [all_inputs]}
  set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
  set arr 0.0
  foreach_in_collection p $paths {set arr [get_attribute $p arrival]}
  set fmax [expr {$arr > 0 ? 1.0/$arr : 0.0}]
  set out ${OUTROOT}/${name}/${corner}
  file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 1 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FU=${name} TOP=${top} TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic"
  close $fh
  echo "RESULT ${name} ${corner} arrival_ns=${arr} fmax_ghz=${fmax}"
}

# Optional: JOB_FILTER=<regexp> reruns only the matching jobs.
if {[info exists ::env(JOB_FILTER)]} { set jobs [lsearch -all -inline -regexp $jobs $::env(JOB_FILTER)] }
# Optional: JOB_REVERSE=1 runs the selected jobs in reverse order.
if {[info exists ::env(JOB_REVERSE)]} { set jobs [lreverse $jobs] }
foreach j $jobs {
  lassign $j name rtl top params
  foreach corner $corners { run_one $name $rtl $top $params $corner }
}
quit
