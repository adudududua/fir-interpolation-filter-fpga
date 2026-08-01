set script_dir [file dirname [file normalize [info script]]]
set nf_dir [file dirname $script_dir]
set out_dir [file join $nf_dir _work x3_20m vivado_core]
open_checkpoint [file join $out_dir x3_20m_core_synth.dcp]

place_design -directive ExtraNetDelay_high
phys_opt_design -directive Explore
route_design -directive Explore

report_utilization -file [file join $out_dir utilization_routed.rpt]
report_utilization -hierarchical -hierarchical_depth 5 \
    -file [file join $out_dir utilization_hier_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 30 \
    -file [file join $out_dir timing_routed.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $out_dir clock_interaction_routed.rpt]
report_cdc -details -file [file join $out_dir cdc_routed.rpt]
report_power -file [file join $out_dir power_vectorless_routed.rpt]
report_drc -file [file join $out_dir drc_routed.rpt]
report_methodology -file [file join $out_dir methodology_routed.rpt]
write_checkpoint -force [file join $out_dir x3_20m_core_routed.dcp]
puts "X3_CORE_ROUTE_COMPLETE: $out_dir"
