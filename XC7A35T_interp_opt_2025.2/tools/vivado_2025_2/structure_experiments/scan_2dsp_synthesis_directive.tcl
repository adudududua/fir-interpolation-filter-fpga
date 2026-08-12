set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set result_dir [file normalize [lindex $argv 0]]
set synthesis_directive [lindex $argv 1]
set jobs [expr {$argc > 2 ? [lindex $argv 2] : 1}]

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

set allowed_directives [list Default AreaOptimized_medium \
    FewerCarryChains AlternateRoutability]
require_condition \
    [expr {[lsearch -exact $allowed_directives $synthesis_directive] >= 0}] \
    "Unsupported synthesis directive: $synthesis_directive"

file mkdir $result_dir
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
    "USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=0"

require_condition [expr {$top_name eq "board_demo_competition_dac8_top"}] \
    "Unexpected top: $top_name"
require_condition \
    [expr {[lsearch -exact $candidate_generics \
        "USE_NATIONAL_FINALS_STAGE2_DATA_W=20"] >= 0}] \
    "The candidate must retain Stage2 signed-20 data."

synth_design -top $top_name -part $part_name \
    -flatten_hierarchy full -directive $synthesis_directive \
    -resource_sharing on -shreg_min_size 5 -generic $candidate_generics
report_utilization -file [file join $result_dir utilization_synthesized.rpt]

opt_design -directive ExploreArea
place_design -directive Explore
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
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

set summary [open [file join $result_dir directive_summary.txt] w]
puts $summary "SYNTHESIS_DIRECTIVE=$synthesis_directive"
puts $summary "LUT=$lut_count"
puts $summary "FF=$ff_count"
puts $summary "DSP48E1=$dsp_count"
puts $summary "RAMB18E1=$bram18_count"
puts $summary "WNS_NS=$wns"
puts $summary "WHS_NS=$whs"
puts $summary "DRC_ERRORS=[llength $drc_errors]"
close $summary

puts "TWO_DSP_DIRECTIVE=$synthesis_directive"
puts "TWO_DSP_DIRECTIVE_LUT=$lut_count"
puts "TWO_DSP_DIRECTIVE_FF=$ff_count"
puts "TWO_DSP_DIRECTIVE_DSP=$dsp_count"
puts "TWO_DSP_DIRECTIVE_BRAM18=$bram18_count"
puts "TWO_DSP_DIRECTIVE_WNS=$wns"
puts "TWO_DSP_DIRECTIVE_WHS=$whs"
puts "TWO_DSP_DIRECTIVE_DRC_ERRORS=[llength $drc_errors]"

require_condition [expr {$dsp_count == 2}] \
    "Expected 2 DSP48E1 cells, got $dsp_count."
require_condition [expr {$bram18_count == 4}] \
    "Expected 4 RAMB18E1 cells, got $bram18_count."
require_condition [expr {$wns >= 0.0 && $whs >= 0.0}] \
    "Timing failed: WNS=$wns WHS=$whs."
require_condition [expr {[llength $drc_errors] == 0}] \
    "DRC contains [llength $drc_errors] error(s)."

puts "TWO_DSP_SYNTHESIS_DIRECTIVE_PASS"
close_design
close_project
exit
