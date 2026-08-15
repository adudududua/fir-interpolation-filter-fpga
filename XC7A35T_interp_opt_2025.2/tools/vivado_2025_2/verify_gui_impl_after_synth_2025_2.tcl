set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set result_dir [expr {$argc > 0 \
    ? [file normalize [lindex $argv 0]] \
    : [file join $script_dir results manual_impl_verify]}]
file mkdir $result_dir

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

open_project $project_file
set_param general.maxThreads 1

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]
set synth_progress [get_property PROGRESS $synth_run]
set synth_status [get_property STATUS $synth_run]
puts "GUI_VERIFY_SYNTH_STATUS=$synth_status"
puts "GUI_VERIFY_SYNTH_PROGRESS=$synth_progress"
require_condition [expr {$synth_progress eq "100%"}] \
    "synth_1 is not complete: status=$synth_status progress=$synth_progress"

set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea $impl_run
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl_run
reset_run $impl_run
launch_runs $impl_run -to_step write_bitstream -jobs 1
wait_on_run $impl_run

set impl_status [get_property STATUS $impl_run]
set impl_progress [get_property PROGRESS $impl_run]
puts "GUI_VERIFY_IMPL_STATUS=$impl_status"
puts "GUI_VERIFY_IMPL_PROGRESS=$impl_progress"
require_condition [expr {$impl_progress eq "100%"}] \
    "impl_1 did not complete: status=$impl_status progress=$impl_progress"

open_run $impl_run
set utilization [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
report_route_status -file [file join $result_dir route_status_routed.rpt]
write_checkpoint -force [file join $result_dir board_routed_2025_2.dcp]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization unused lut_count] \
    "Could not parse routed Slice LUT count."
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization unused ff_count] \
    "Could not parse routed Slice Register count."

set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

puts "GUI_VERIFY_LUT=$lut_count"
puts "GUI_VERIFY_FF=$ff_count"
puts "GUI_VERIFY_DSP=$dsp_count"
puts "GUI_VERIFY_BRAM18=$bram18_count"
puts "GUI_VERIFY_MMCM=$mmcm_count"
puts "GUI_VERIFY_WNS=$wns"
puts "GUI_VERIFY_WHS=$whs"
puts "GUI_VERIFY_DRC_ERRORS=[llength $drc_errors]"

require_condition [expr {$lut_count <= 218}] \
    "Routed LUT regression: expected no more than 218, got $lut_count."
require_condition [expr {$ff_count <= 365}] \
    "Routed FF regression: expected no more than 365, got $ff_count."
require_condition [expr {$dsp_count == 4}] "Expected exactly 4 DSP48E1 cells."
require_condition [expr {$bram18_count == 4}] "Expected exactly 4 RAMB18E1 cells."
require_condition [expr {$mmcm_count == 2}] "Expected exactly 2 MMCME2_ADV cells."
require_condition [expr {$wns >= 0.0}] "Setup timing failed: WNS=$wns ns."
require_condition [expr {$whs >= 0.0}] "Hold timing failed: WHS=$whs ns."
require_condition [expr {[llength $drc_errors] == 0}] \
    "DRC contains [llength $drc_errors] error(s)."

set source_bit [file join $project_dir XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
set result_bit [file join $result_dir board_demo_competition_dac8_top_2025_2.bit]
require_condition [file exists $source_bit] "GUI bitstream is missing: $source_bit"
file copy -force $source_bit $result_bit

puts "VERIFY_GUI_IMPL_AFTER_SYNTH_2025_2_PASS"
close_design
close_project
exit
