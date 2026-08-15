set input_dcp [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set recipe [lindex $argv 2]
set jobs [expr {$argc > 3 ? [lindex $argv 3] : 1}]
file mkdir $output_dir

proc require_condition {condition message} {
    if {!$condition} { error $message }
}

require_condition [file exists $input_dcp] "Missing synthesized DCP: $input_dcp"
require_condition [expr {$recipe in {explore default extra_timing}}] \
    "recipe must be explore, default, or extra_timing"
set_param general.maxThreads $jobs
open_checkpoint $input_dcp

opt_design -directive ExploreArea
if {$recipe eq "explore"} {
    place_design -directive Explore
} elseif {$recipe eq "default"} {
    place_design -directive Default
} else {
    place_design -directive ExtraTimingOpt
}
route_design

set utilization [report_utilization -return_string]
report_utilization -file [file join $output_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $output_dir timing_summary_routed.rpt]
report_route_status -file [file join $output_dir route_status_routed.rpt]
report_drc -file [file join $output_dir drc_routed.rpt]
write_checkpoint -force [file join $output_dir board_routed.dcp]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization unused lut_count] "Could not parse LUT count"
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization unused ff_count] "Could not parse FF count"
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

set fid [open [file join $output_dir recipe_summary.txt] w]
puts $fid "INPUT_DCP=$input_dcp"
puts $fid "RECIPE=$recipe"
puts $fid "LUT=$lut_count"
puts $fid "FF=$ff_count"
puts $fid "DSP48E1=$dsp_count"
puts $fid "RAMB18E1=$bram18_count"
puts $fid "WNS_NS=$wns"
puts $fid "WHS_NS=$whs"
puts $fid "DRC_ERRORS=[llength $drc_errors]"
close $fid

require_condition [expr {$wns >= 0.0}] "Setup timing failed: $wns"
require_condition [expr {$whs >= 0.0}] "Hold timing failed: $whs"
require_condition [expr {[llength $drc_errors] == 0}] "DRC errors found"
puts "REROUTE_RECIPE_PASS=$recipe,$lut_count,$ff_count,$wns,$whs"
close_design
exit
