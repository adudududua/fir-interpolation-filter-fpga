set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set result_dir [file join $script_dir results active_239lut_3dsp]
file mkdir $result_dir

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

if {[current_project -quiet] eq ""} {
    open_project [file join $project_dir XC7A35T_interp.xpr]
}

set top_name [get_property TOP [get_filesets sources_1]]
set part_name [get_property PART [current_project]]
set source_generics [get_property GENERIC [get_filesets sources_1]]
require_condition [expr {$top_name eq "board_demo_competition_dac8_top"}] \
    "Unexpected board top: $top_name"
require_condition \
    [expr {[lsearch -exact $source_generics \
        "USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=1"] >= 0}] \
    "The project does not select the 239-LUT / 3-DSP CIC mapping."
require_condition \
    [expr {[lsearch -exact $source_generics \
        "USE_NATIONAL_FINALS_STAGE2_DATA_W=20"] >= 0}] \
    "The project does not retain Stage2 signed-20 data."

if {[current_design -quiet] ne ""} {
    close_design
}
set_param general.maxThreads 1

synth_design -top $top_name -part $part_name \
    -flatten_hierarchy full -directive AreaOptimized_high \
    -resource_sharing on -shreg_min_size 5 -generic $source_generics
report_utilization -file [file join $result_dir utilization_synthesized.rpt]
write_checkpoint -force [file join $result_dir board_synthesized_239lut_3dsp.dcp]

opt_design -directive ExploreArea
place_design -directive Explore
route_design

set utilization_report [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_routed.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_bus_skew -file [file join $result_dir bus_skew_routed.rpt]
report_route_status -file [file join $result_dir route_status_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
report_cdc -details -file [file join $result_dir cdc_routed.rpt]
report_methodology -file [file join $result_dir methodology_routed.rpt]
check_timing -verbose -file [file join $result_dir check_timing_routed.rpt]
report_power -file [file join $result_dir power_routed.rpt]
write_checkpoint -force [file join $result_dir board_routed_239lut_3dsp.dcp]

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

require_condition [expr {$lut_count == 239}] \
    "Expected 239 LUT, got $lut_count."
require_condition [expr {$ff_count == 388}] \
    "Expected 388 FF, got $ff_count."
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

set bit_file [file join $result_dir board_demo_competition_dac8_top_239lut_3dsp.bit]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force $bit_file
require_condition [file exists $bit_file] "Expected bitstream is missing."

set summary [open [file join $result_dir ACTIVE_CONFIGURATION.txt] w]
puts $summary "CONFIG_ID=NF-P3-STAGE123-24-20-20-3DSP-PARETO-R1"
puts $summary "CIC_INTEGRATOR_DSP_MODE=1"
puts $summary "LUT=$lut_count"
puts $summary "FF=$ff_count"
puts $summary "DSP48E1=$dsp_count"
puts $summary "RAMB18E1=$bram18_count"
puts $summary "MMCM=$mmcm_count"
puts $summary "WNS_NS=$wns"
puts $summary "WHS_NS=$whs"
puts $summary "DRC_ERRORS=[llength $drc_errors]"
puts $summary "BITSTREAM=$bit_file"
close $summary

puts "ACTIVE_239LUT_3DSP_LUT=$lut_count"
puts "ACTIVE_239LUT_3DSP_FF=$ff_count"
puts "ACTIVE_239LUT_3DSP_DSP=$dsp_count"
puts "ACTIVE_239LUT_3DSP_WNS=$wns"
puts "ACTIVE_239LUT_3DSP_WHS=$whs"
puts "ACTIVE_239LUT_3DSP_BUILD_PASS"
