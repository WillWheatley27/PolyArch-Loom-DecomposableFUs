# Normalized 64/32-only Karatsuba multiplier comparison.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/mult_karatsuba_64_32_comparison
file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR ${ROOT}/rtl]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

set jobs {
  {karatsuba_decomposable decomposable 64_32 rtl/fu_mult_karatsuba_64_32.sv fu_mult_karatsuba_64_32}
  {karatsuba_fixed_64 fixed_karatsuba 64 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_64.sv fu_mult_karatsuba_64}
  {karatsuba_fixed_32x2 fixed_karatsuba 32x2 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_32x2.sv fu_mult_karatsuba_32x2}
  {designware_fixed_64 fixed_designware 64 rtl/standalone/mult_standalones/fu_mult_64.sv fu_mult_64}
  {designware_fixed_32x2 fixed_designware 32x2 rtl/standalone/mult_standalones/fu_mult_32x2.sv fu_mult_32x2}
}

proc run_one {name kind capability rtl_rel top corner period outroot} {
  global ROOT
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
  set out ${outroot}/${corner}/${name}
  file mkdir $out
  report_area > ${out}/report_area.rpt
  report_power -analysis_effort low > ${out}/report_power.rpt
  report_timing -delay_type max -nworst 10 > ${out}/report_timing.rpt
  set fh [open ${out}/result.txt w]
  puts $fh "FU=Mult64_32 NAME=${name} KIND=${kind} CAPABILITY=${capability} TOP=${top} CORNER=${corner} TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arr} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic PVT=tt0p8v25c LIBRARY=saed14rvt_base_tt0p8v25c.db"
  close $fh
  echo "RESULT ${corner} ${name} arrival_ns=${arr} fmax_ghz=${fmax}"
}

foreach job $jobs {
  lassign $job name kind capability rtl top
  run_one $name $kind $capability $rtl $top one_ghz 1.000 $OUTROOT
  run_one $name $kind $capability $rtl $top two_ghz 0.500 $OUTROOT
}
quit
