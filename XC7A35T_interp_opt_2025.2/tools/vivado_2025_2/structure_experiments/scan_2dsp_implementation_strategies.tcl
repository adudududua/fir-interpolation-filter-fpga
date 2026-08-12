set_param general.maxThreads 1

if {$argc < 4} {
    error "usage: scan_2dsp_implementation_strategies.tcl <synth.dcp> <result_dir> <opt_directive> <place_directive>"
}

set synth_dcp [file normalize [lindex $argv 0]]
set result_dir [file normalize [lindex $argv 1]]
set opt_directive [lindex $argv 2]
set place_directive [lindex $argv 3]
file mkdir $result_dir

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

open_checkpoint $synth_dcp

if {$opt_directive eq "Default"} {
    opt_design
} else {
    opt_design -directive $opt_directive
}
if {$place_directive eq "Default"} {
    place_design
} else {
    place_design -directive $place_directive
}
route_design

set utilization_report [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused lut_count] \
    "Could not parse Slice LUT count."
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused ff_count] \
    "Could not parse Slice Register count."

set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
require_condition [expr {[llength $setup_path] == 1}] \
    "No setup timing path was found."
require_condition [expr {[llength $hold_path] == 1}] \
    "No hold timing path was found."
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

set summary [open [file join $result_dir strategy_summary.txt] w]
puts $summary "OPT_DIRECTIVE=$opt_directive"
puts $summary "PLACE_DIRECTIVE=$place_directive"
puts $summary "LUT=$lut_count"
puts $summary "FF=$ff_count"
puts $summary "DSP48E1=$dsp_count"
puts $summary "RAMB18E1=$bram18_count"
puts $summary "WNS_NS=$wns"
puts $summary "WHS_NS=$whs"
puts $summary "DRC_ERRORS=[llength $drc_errors]"
close $summary

puts "TWO_DSP_STRATEGY_OPT=$opt_directive"
puts "TWO_DSP_STRATEGY_PLACE=$place_directive"
puts "TWO_DSP_STRATEGY_LUT=$lut_count"
puts "TWO_DSP_STRATEGY_FF=$ff_count"
puts "TWO_DSP_STRATEGY_DSP=$dsp_count"
puts "TWO_DSP_STRATEGY_BRAM18=$bram18_count"
puts "TWO_DSP_STRATEGY_WNS=$wns"
puts "TWO_DSP_STRATEGY_WHS=$whs"
puts "TWO_DSP_STRATEGY_DRC_ERRORS=[llength $drc_errors]"

require_condition [expr {$dsp_count == 2}] \
    "Expected 2 DSP48E1 cells, got $dsp_count."
require_condition [expr {$bram18_count == 4}] \
    "Expected 4 RAMB18E1 cells, got $bram18_count."
require_condition [expr {$wns >= 0.0}] "Setup timing failed: $wns ns."
require_condition [expr {$whs >= 0.0}] "Hold timing failed: $whs ns."
require_condition [expr {[llength $drc_errors] == 0}] \
    "DRC contains [llength $drc_errors] error(s)."

puts "TWO_DSP_STRATEGY_PASS"
close_design
exit
