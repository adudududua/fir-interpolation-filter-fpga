set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set result_dir [expr {$argc > 0 ? [file normalize [lindex $argv 0]] : \
    [file join $script_dir results cic_dsp_pareto]}]
set integrator_dsp_mode [expr {$argc > 1 ? [lindex $argv 1] : 1}]
set jobs [expr {$argc > 2 ? [lindex $argv 2] : 1}]

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

require_condition \
    [expr {$integrator_dsp_mode == 0 || $integrator_dsp_mode == 1}] \
    "CIC Pareto mode must be 0 or 1."
file mkdir $result_dir

puts "CIC_PARETO_PROJECT=$project_file"
puts "CIC_PARETO_RESULT_DIR=$result_dir"
puts "CIC_PARETO_INTEGRATOR_DSP_MODE=$integrator_dsp_mode"
puts "CIC_PARETO_JOBS=$jobs"

open_project -read_only $project_file
set_param general.maxThreads $jobs

set top_name [get_property TOP [get_filesets sources_1]]
set part_name [get_property PART [current_project]]
set base_generics [get_property GENERIC [get_filesets sources_1]]
set candidate_generics [list]
foreach generic_value $base_generics {
    if {![string match \
            "USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=*" \
            $generic_value]} {
        lappend candidate_generics $generic_value
    }
}
lappend candidate_generics \
    "USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=$integrator_dsp_mode"

require_condition [expr {$top_name eq "board_demo_competition_dac8_top"}] \
    "Unexpected top: $top_name"
require_condition \
    [expr {[lsearch -exact $candidate_generics \
        "USE_NATIONAL_FINALS_STAGE2_DATA_W=20"] >= 0}] \
    "The experiment must retain Stage2 signed-20 data."

set manifest [open [file join $result_dir experiment_config.txt] w]
puts $manifest "BASE=218-LUT 24/20/20 board-pass"
puts $manifest "TOP=$top_name"
puts $manifest "CIC_INTEGRATOR_DSP_MODE=$integrator_dsp_mode"
puts $manifest "GENERICS=$candidate_generics"
close $manifest

synth_design -top $top_name -part $part_name \
    -flatten_hierarchy full -directive AreaOptimized_high \
    -resource_sharing on -shreg_min_size 5 -generic $candidate_generics
report_utilization -file [file join $result_dir utilization_synthesized.rpt]
write_checkpoint -force [file join $result_dir board_synthesized.dcp]

opt_design -directive ExploreArea
place_design -directive Explore
route_design

set utilization_report [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_routed.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_route_status -file [file join $result_dir route_status_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
report_power -file [file join $result_dir power_routed.rpt]
write_checkpoint -force [file join $result_dir board_routed.dcp]

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
set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
require_condition [expr {[llength $setup_path] == 1}] \
    "No setup timing path was found."
require_condition [expr {[llength $hold_path] == 1}] \
    "No hold timing path was found."
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set expected_dsp_count [expr {2 + $integrator_dsp_mode}]

set summary [open [file join $result_dir pareto_summary.txt] w]
puts $summary "CIC_INTEGRATOR_DSP_MODE=$integrator_dsp_mode"
puts $summary "LUT=$lut_count"
puts $summary "FF=$ff_count"
puts $summary "DSP48E1=$dsp_count"
puts $summary "RAMB18E1=$bram18_count"
puts $summary "MMCM=$mmcm_count"
puts $summary "WNS_NS=$wns"
puts $summary "WHS_NS=$whs"
puts $summary "DRC_ERRORS=[llength $drc_errors]"
close $summary

puts "CIC_PARETO_LUT=$lut_count"
puts "CIC_PARETO_FF=$ff_count"
puts "CIC_PARETO_DSP=$dsp_count"
puts "CIC_PARETO_BRAM18=$bram18_count"
puts "CIC_PARETO_MMCM=$mmcm_count"
puts "CIC_PARETO_WNS=$wns"
puts "CIC_PARETO_WHS=$whs"
puts "CIC_PARETO_DRC_ERRORS=[llength $drc_errors]"

require_condition [expr {$dsp_count == $expected_dsp_count}] \
    "Expected $expected_dsp_count DSP48E1 cells, got $dsp_count."
require_condition [expr {$bram18_count == 4}] \
    "Expected 4 RAMB18E1 cells, got $bram18_count."
require_condition [expr {$mmcm_count == 2}] \
    "Expected 2 MMCME2_ADV cells, got $mmcm_count."
require_condition [expr {$wns >= 0.0}] "Setup timing failed: $wns ns."
require_condition [expr {$whs >= 0.0}] "Hold timing failed: $whs ns."
require_condition [expr {[llength $drc_errors] == 0}] \
    "DRC contains [llength $drc_errors] error(s)."

puts "CIC_DSP_PARETO_BUILD_PASS"
close_design
close_project
exit
