set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set original_cic [file join $source_root national_finals \
    cic_interp16_n3_hold2_dsp_ce.v]
set packed_rom [file join $source_root national_finals \
    nf_sine_15k_dual_rate_packed32_256.mem]
set candidate_core [file join $script_dir \
    cic_interp16_n3_hold2_integrator_pair_mode1_candidate.v]
set candidate_pair [file join $script_dir \
    nf_cic_two24_integrator_pair_mode1.v]
set candidate_adapter [file join $script_dir \
    cic_integrator_pair_mode1_dropin_adapter.v]
set result_dir [expr {$argc > 0 ? [file normalize [lindex $argv 0]] : \
    [file join $script_dir results three_dsp_integrator_pair]}]
set jobs [expr {$argc > 1 ? [lindex $argv 1] : 1}]

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

foreach required_file [list $project_file $original_cic $packed_rom \
        $candidate_core $candidate_pair $candidate_adapter] {
    require_condition [file isfile $required_file] \
        "Missing required file: $required_file"
}

file mkdir $result_dir
open_project -read_only $project_file
set sandbox_dir [file join $project_dir .three_dsp_pair_sandbox]
if {[file exists $sandbox_dir]} {
    file delete -force $sandbox_dir
}
file mkdir $sandbox_dir
save_project_as -force sandbox $sandbox_dir
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
    "USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=1"

require_condition [expr {$top_name eq "board_demo_competition_dac8_top"}] \
    "Unexpected top: $top_name"
require_condition \
    [expr {[lsearch -exact $candidate_generics \
        "USE_NATIONAL_FINALS_STAGE2_DATA_W=20"] >= 0}] \
    "The candidate must retain Stage2 signed-20 data."

set original_cic_file [get_files -quiet \
    *national_finals/cic_interp16_n3_hold2_dsp_ce.v]
require_condition [expr {[llength $original_cic_file] == 1}] \
    "Could not identify exactly one original CIC source."
remove_files $original_cic_file

foreach candidate_file [list $candidate_core $candidate_pair \
        $candidate_adapter] {
    add_files -norecurse $candidate_file
    set_property USED_IN_SIMULATION false [get_files $candidate_file]
    set_property FILE_TYPE {Verilog} [get_files $candidate_file]
    set_property library xil_defaultlib [get_files $candidate_file]
}

# The current board top names the packed ROM by basename.  The signed-off
# project keeps the file beside the RTL but does not list it in the XPR, so an
# isolated save-as must add it explicitly to avoid a false 3-BRAM result.
if {[llength [get_files -quiet *nf_sine_15k_dual_rate_packed32_256.mem]] == 0} {
    add_files -norecurse $packed_rom
}
set_property FILE_TYPE {Memory Initialization Files} \
    [get_files *nf_sine_15k_dual_rate_packed32_256.mem]

set manifest [open [file join $result_dir experiment_config.txt] w]
puts $manifest "BASE=239-LUT 24/20/20 3-DSP tool-verified"
puts $manifest "CANDIDATE=TWO24 exact dual-integrator state transform"
puts $manifest "TOP=$top_name"
puts $manifest "GENERICS=$candidate_generics"
puts $manifest "CORE=$candidate_core"
puts $manifest "PAIR=$candidate_pair"
puts $manifest "ADAPTER=$candidate_adapter"
puts $manifest "PACKED_ROM=$packed_rom"
close $manifest

synth_design -top $top_name -part $part_name \
    -flatten_hierarchy full -directive AreaOptimized_high \
    -resource_sharing on -shreg_min_size 5 -generic $candidate_generics
report_utilization -file [file join $result_dir utilization_synthesized.rpt]

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

set summary [open [file join $result_dir candidate_summary.txt] w]
puts $summary "LUT=$lut_count"
puts $summary "FF=$ff_count"
puts $summary "DSP48E1=$dsp_count"
puts $summary "RAMB18E1=$bram18_count"
puts $summary "MMCM=$mmcm_count"
puts $summary "WNS_NS=$wns"
puts $summary "WHS_NS=$whs"
puts $summary "DRC_ERRORS=[llength $drc_errors]"
close $summary

puts "THREE_DSP_PAIR_LUT=$lut_count"
puts "THREE_DSP_PAIR_FF=$ff_count"
puts "THREE_DSP_PAIR_DSP=$dsp_count"
puts "THREE_DSP_PAIR_BRAM18=$bram18_count"
puts "THREE_DSP_PAIR_WNS=$wns"
puts "THREE_DSP_PAIR_WHS=$whs"
puts "THREE_DSP_PAIR_DRC_ERRORS=[llength $drc_errors]"

require_condition [expr {$dsp_count == 3}] \
    "Expected 3 DSP48E1 cells, got $dsp_count."
require_condition [expr {$bram18_count == 4}] \
    "Expected 4 RAMB18E1 cells, got $bram18_count."
require_condition [expr {$mmcm_count == 2}] \
    "Expected 2 MMCME2_ADV cells, got $mmcm_count."
require_condition [expr {$wns >= 0.0}] "Setup timing failed: $wns ns."
require_condition [expr {$whs >= 0.0}] "Hold timing failed: $whs ns."
require_condition [expr {[llength $drc_errors] == 0}] \
    "DRC contains [llength $drc_errors] error(s)."
require_condition [expr {$lut_count < 239}] \
    "Candidate did not improve the 239-LUT baseline."

puts "THREE_DSP_PAIR_CANDIDATE_PASS"
close_design
close_project
exit
