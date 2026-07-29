# Low-memory single-process implementation.
#
# Vivado project runs keep a launcher and implementation process resident at
# the same time. On memory-constrained Windows hosts that can make 2018.3 abort
# even for a small XC7A35T design. This script reuses the completed synthesis
# checkpoint and performs opt/place/route/report/bitstream in one process.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt]
set synth_dcp [file join $project_dir XC7A35T_interp.runs synth_1 \
    board_demo_competition_dac8_top.dcp]
set board_xdc [file join $project_dir XC7A35T_interp.srcs constrs_1 new \
    board_demo_competition_dac8_top.xdc]
set result_tag board_dual_rate_areaopt
set architecture cic
set all2x_shared_tail 1
set all2x_tail_dsp48 0
set packed_stage23 0
set synthesis_directive AreaOptimized_high
set flatten_hierarchy rebuilt
set resource_sharing on
if {$argc > 0} {
    set result_tag [lindex $argv 0]
}
if {$argc > 1} {
    set architecture [lindex $argv 1]
}
if {$argc > 2} {
    set all2x_shared_tail [lindex $argv 2]
}
if {$argc > 3} {
    set all2x_tail_dsp48 [lindex $argv 3]
}
if {$argc > 4} {
    set packed_stage23 [lindex $argv 4]
}
if {$argc > 5} {
    set synthesis_directive [lindex $argv 5]
}
if {$argc > 6} {
    set flatten_hierarchy [lindex $argv 6]
}
if {$argc > 7} {
    set resource_sharing [lindex $argv 7]
}
if {![regexp {^[A-Za-z0-9_-]+$} $result_tag]} {
    error "result_tag may contain only letters, digits, underscore, and dash"
}
if {$architecture != "cic" && $architecture != "all2x"} {
    error "architecture must be cic or all2x"
}
set result_dir [file normalize [file join $script_dir .. vivado_results \
    $result_tag]]

proc require_file {filename} {
    if {![file exists $filename]} {
        error "Required file does not exist: $filename"
    }
}

proc write_primitive_report {report_file pattern title} {
    set primitive_cells [get_cells -hierarchical \
        -filter [format {REF_NAME =~ %s} $pattern]]
    set report_handle [open $report_file w]
    puts $report_handle $title
    puts $report_handle [string repeat "=" [string length $title]]
    puts $report_handle "Cell count: [llength $primitive_cells]"
    foreach primitive_cell $primitive_cells {
        puts $report_handle [format "%s | %s | %s" \
            $primitive_cell \
            [get_property REF_NAME $primitive_cell] \
            [get_property LOC $primitive_cell]]
    }
    close $report_handle
}

require_file $synth_dcp
require_file $board_xdc
file mkdir $result_dir

open_checkpoint $synth_dcp
read_xdc $board_xdc

opt_design -directive ExploreArea
place_design
route_design

set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
set setup_slack [get_property SLACK $setup_path]
set hold_slack [get_property SLACK $hold_path]

write_checkpoint -force \
    [file join $result_dir national_finals_board_routed.dcp]

if {$setup_slack < 0.0 || $hold_slack < 0.0} {
    error [format \
        "Timing failed after routing: setup slack %.3f ns, hold slack %.3f ns" \
        $setup_slack $hold_slack]
}

if {$architecture == "all2x"} {
    set bitstream_name national_finals_dual_rate_4x8x128x_all2x_areaopt.bit
} else {
    set bitstream_name national_finals_dual_rate_4x8x128x_areaopt.bit
}
set bitstream_dst [file join $result_dir $bitstream_name]
write_bitstream -force $bitstream_dst

report_clocks -file [file join $result_dir clock_report_routed.rpt]
report_utilization -file [file join $result_dir utilization_placed.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 30 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $result_dir clock_interaction_routed.rpt]
report_route_status -file [file join $result_dir route_status_routed.rpt]
report_power -file [file join $result_dir power_vectorless_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]

write_primitive_report \
    [file join $result_dir dsp_utilization_routed.rpt] \
    "DSP48*" "National-finals DSP utilization"
write_primitive_report \
    [file join $result_dir bram_utilization_routed.rpt] \
    "RAMB*" "National-finals BRAM utilization"
write_primitive_report \
    [file join $result_dir mmcm_utilization_routed.rpt] \
    "MMCME2*" "National-finals MMCM utilization"

set manifest_handle [open [file join $result_dir build_manifest.txt] w]
puts $manifest_handle "National-finals dual-rate board build"
puts $manifest_handle "Synthesis checkpoint: $synth_dcp"
puts $manifest_handle "Part: [get_property PART [current_design]]"
puts $manifest_handle "Top: board_demo_competition_dac8_top"
puts $manifest_handle "Bitstream: $bitstream_dst"
puts $manifest_handle [format "Routed setup slack: %.3f ns" $setup_slack]
puts $manifest_handle [format "Routed hold slack: %.3f ns" $hold_slack]
puts $manifest_handle "44.1-kHz family 128x clock: 5.644796 MHz (-0.64 ppm nominal)"
puts $manifest_handle "48-kHz family 128x clock: 6.144068 MHz (+11.03 ppm nominal)"
if {$architecture == "all2x"} {
    puts $manifest_handle "Architecture: seven 2x FIR stages with shared Stage2/3 DSP and shared Stage4-7 shift-add datapath"
    puts $manifest_handle "All-2x shared Stage4-7 datapath: $all2x_shared_tail"
    puts $manifest_handle "All-2x Stage4-7 DSP48 pre-adder: $all2x_tail_dsp48"
} else {
    puts $manifest_handle "Architecture: shared 2x/2x/2x FIR + shift-add CIC equalizer + CIC16"
}
puts $manifest_handle "Packed Stage2/3 BRAM: $packed_stage23"
puts $manifest_handle "Synthesis directive: $synthesis_directive"
puts $manifest_handle "Flatten hierarchy: $flatten_hierarchy"
puts $manifest_handle "Synthesis resource sharing: $resource_sharing"
puts $manifest_handle "Implementation opt directive: ExploreArea"
close $manifest_handle

puts "NATIONAL_FINALS_SINGLE_PROCESS_BUILD_PASS"
puts [format "SETUP_SLACK_NS=%.3f" $setup_slack]
puts [format "HOLD_SLACK_NS=%.3f" $hold_slack]
puts "RESULT_DIR=$result_dir"
puts "BITSTREAM=$bitstream_dst"
close_design
