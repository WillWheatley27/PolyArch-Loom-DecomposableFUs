# Controlled SAED14nm comparison for the decomposable Karatsuba multiplier,
# a fixed Karatsuba bank, and the existing fixed DesignWare bank.
#
# one_ghz is the primary equal-frequency comparison.  maxspeed applies the
# same intentionally impossible 0.010 ns stress target to expose timing-driven
# sizing and achieved Fmax; it is not an equal-achieved-frequency power run.
set LIB_DIR /mnt/nas0/eda.libs/saed14/EDK_03_2025/SAED14nm_EDK_STD_RVT/liberty/nldm/base
set LIB saed14rvt_base_tt0p8v25c.db
set ROOT /edata1/will/Decomposable_FU
set OUTROOT ${ROOT}/reports/mult_karatsuba_comparison

file mkdir $OUTROOT
set search_path [concat $search_path $LIB_DIR]
set link_library [list * $LIB]
set target_library [list $LIB]
set_app_var hdlin_sverilog_std 2017

# name | implementation | capability | RTL | top
set jobs {
  {karatsuba_decomposable decomposable 64/32x2/16x4 rtl/fu_mult_decomp.sv fu_mult_decomp}
  {karatsuba_fixed_64 karatsuba_fixed 64 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_64.sv fu_mult_karatsuba_64}
  {karatsuba_fixed_32x2 karatsuba_fixed 32x2 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_32x2.sv fu_mult_karatsuba_32x2}
  {karatsuba_fixed_16x4 karatsuba_fixed 16x4 rtl/standalone/mult_karatsuba_standalones/fu_mult_karatsuba_16x4.sv fu_mult_karatsuba_16x4}
  {designware_fixed_64 designware_fixed 64 rtl/standalone/mult_standalones/fu_mult_64.sv fu_mult_64}
  {designware_fixed_32x2 designware_fixed 32x2 rtl/standalone/mult_standalones/fu_mult_32x2.sv fu_mult_32x2}
  {designware_fixed_16x4 designware_fixed 16x4 rtl/standalone/mult_standalones/fu_mult_16x4.sv fu_mult_16x4}
}

proc run_one {name implementation capability rtl_rel top corner period area_effort outroot} {
  global ROOT
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

  # Comparable synthetic activity, not workload-derived SAIF/VCD power.
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
  puts $fh "FU=Mult NAME=${name} IMPLEMENTATION=${implementation} CAPABILITY=${capability} TOP=${top} CORNER=${corner} TARGET_PERIOD_NS=${period} ARRIVAL_NS=${arrival} FMAX_GHZ=${fmax} ACTIVITY_SOURCE=uniform_synthetic PVT=tt0p8v25c LIBRARY=saed14rvt_base_tt0p8v25c.db"
  close $fh
  echo "RESULT ${corner} ${name} arrival_ns=${arrival} fmax_ghz=${fmax}"
}

foreach job $jobs {
  lassign $job name implementation capability rtl top
  run_one $name $implementation $capability $rtl $top one_ghz 1.000 1 $OUTROOT
  run_one $name $implementation $capability $rtl $top maxspeed 0.010 0 $OUTROOT
}
quit
