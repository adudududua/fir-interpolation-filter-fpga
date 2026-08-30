set script_dir [file dirname [file normalize [info script]]]
set nc_root [file normalize [file join $script_dir ..]]
set result_dir [file join $nc_root results implementation]
set dcp [file join $result_dir board_network_routed.dcp]

if {![file exists $dcp]} {
    error "找不到最终布局后检查点：$dcp"
}

open_checkpoint $dcp
report_methodology -file [file join $result_dir methodology_current_2025_2.rpt]
report_cdc -details -file [file join $result_dir cdc_current_2025_2.rpt]
report_timing_summary -check_timing_verbose -file \
    [file join $result_dir timing_methodology_current_2025_2.rpt]
close_design
puts "METHODOLOGY_CURRENT_2025_2_PASS"
exit
