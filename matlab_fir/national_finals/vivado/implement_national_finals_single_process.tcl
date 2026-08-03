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
set result_tag board_dual_rate_cic6_round7_headroom_opt
set implementation_opt_directive Default
set p3_joint_stage3 1
set expected_synth_directive AreaOptimized_high
set expected_flatten_hierarchy full
set expected_resource_sharing on
set expected_stage1_dsp48_preadder 1
set expected_cic_integrator_dsp_mode 2
set expected_stage1_single_bram 1
set expected_stage23_unified_bram 1
if {$argc > 0} {
    set result_tag [lindex $argv 0]
}
if {$argc > 1} {
    set implementation_opt_directive [lindex $argv 1]
}
if {$argc > 2} {
    set p3_joint_stage3 [lindex $argv 2]
}
if {$argc > 3} {
    set expected_synth_directive [lindex $argv 3]
}
if {$argc > 4} {
    set expected_flatten_hierarchy [lindex $argv 4]
}
if {$argc > 5} {
    set expected_resource_sharing [lindex $argv 5]
}
if {$argc > 6} {
    set expected_stage1_dsp48_preadder [lindex $argv 6]
}
if {$argc > 7} {
    set expected_cic_integrator_dsp_mode [lindex $argv 7]
}
if {$argc > 8} {
    set expected_stage1_single_bram [lindex $argv 8]
}
if {$argc > 9} {
    set expected_stage23_unified_bram [lindex $argv 9]
}
if {![regexp {^[A-Za-z0-9_-]+$} $result_tag]} {
    error "result_tag may contain only letters, digits, underscore, and dash"
}
if {$implementation_opt_directive ni \
    {Default Explore ExploreWithRemap ExploreArea AddRemap}} {
    error "Unsupported implementation opt directive: $implementation_opt_directive"
}
if {$p3_joint_stage3 != 0 && $p3_joint_stage3 != 1} {
    error "p3_joint_stage3 must be 0 or 1"
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
set synth_provenance_file [file join $project_dir XC7A35T_interp.runs synth_1 \
    national_finals_synth_provenance.txt]
require_file $synth_provenance_file
set expected_synth_provenance [join [list \
    "synth_directive=$expected_synth_directive" \
    "flatten_hierarchy=$expected_flatten_hierarchy" \
    "resource_sharing=$expected_resource_sharing" \
    "stage1_dsp48_preadder=$expected_stage1_dsp48_preadder" \
    "cic_integrator_dsp_mode=$expected_cic_integrator_dsp_mode" \
    "p3_joint_stage3=$p3_joint_stage3" \
    "stage1_single_bram=$expected_stage1_single_bram" \
    "stage23_unified_bram=$expected_stage23_unified_bram"] "\n"]
set synth_provenance_handle [open $synth_provenance_file r]
set actual_synth_provenance [string trim [read $synth_provenance_handle]]
close $synth_provenance_handle
if {$actual_synth_provenance ne $expected_synth_provenance} {
    error "Synthesis checkpoint provenance mismatch. Re-run synthesis with the requested profile before implementation. Expected:\n$expected_synth_provenance\nActual:\n$actual_synth_provenance"
}
file mkdir $result_dir

open_checkpoint $synth_dcp
read_xdc $board_xdc

# Vivado 2018.3 XDC accepts constraint commands but not Tcl `if'.  Keep the
# endpoint drift assertions in the build script after the XDC has resolved.
set ctrl_to_audio_sync_pins [get_pins -hierarchical -regexp \
    {.*(family_audio_meta_reg|rst_request_sync_reg\[0\]|u_nf_mode_cdc_handshake/req_meta_reg)/D}]
set audio_to_ctrl_sync_pins [get_pins -hierarchical -regexp \
    {.*u_nf_mode_cdc_handshake/ack_meta_reg/D}]
set bufgmux_select_pins [get_pins -hierarchical -regexp \
    {.*u_dual_family_audio_clock/u_bufgmux_audio_family/S[01]}]
set mode_shadow_cells [get_cells -hierarchical -regexp \
    {.*u_nf_mode_cdc_handshake/mode_shadow_reg\[[01]\]}]
set audio_mode_cells [get_cells -hierarchical -regexp \
    {.*u_nf_mode_cdc_handshake/audio_mode_reg\[[01]\]}]
if {[llength $ctrl_to_audio_sync_pins] != 3 || \
        [llength $audio_to_ctrl_sync_pins] != 1 || \
        [llength $bufgmux_select_pins] != 2 || \
        [llength $mode_shadow_cells] != 2 || \
        [llength $audio_mode_cells] != 2} {
    error "Audited CDC endpoint set changed; update constraints and waivers"
}

proc write_text_report {report_file report_text} {
    set report_handle [open $report_file w]
    puts -nonewline $report_handle $report_text
    close $report_handle
}

if {$implementation_opt_directive eq "Default"} {
    opt_design
} else {
    opt_design -directive $implementation_opt_directive
}
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

set bitstream_dst [file join $result_dir \
    national_finals_dual_rate_4x8x128x_areaopt.bit]
write_bitstream -force $bitstream_dst

report_clocks -file [file join $result_dir clock_report_routed.rpt]
report_utilization -file [file join $result_dir utilization_placed.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 30 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_timing -to [get_ports {dac_data[*]}] -delay_type max -max_paths 8 \
    -file [file join $result_dir dac_output_setup_routed.rpt]
report_timing -to [get_ports {dac_data[*]}] -delay_type min -max_paths 8 \
    -file [file join $result_dir dac_output_hold_routed.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $result_dir clock_interaction_routed.rpt]
report_route_status -file [file join $result_dir route_status_routed.rpt]
report_power -file [file join $result_dir power_vectorless_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
set methodology_text [report_methodology -return_string]
write_text_report [file join $result_dir methodology_routed.rpt] \
    $methodology_text
if {![regexp {\| TIMING-18 \| Warning\s+\|[^\n]+\| 8\s+\|} \
        $methodology_text]} {
    error "Methodology warning set changed: expected TIMING-18 count 8"
}
set cdc_text [report_cdc -details -return_string]
write_text_report [file join $result_dir cdc_routed.rpt] $cdc_text
foreach expected_cdc_pattern [list \
        {CDC-3\s+Info\s+10\s} \
        {CDC-13\s+Critical\s+2\s} \
        {CDC-15\s+Warning\s+4\s}] {
    if {![regexp $expected_cdc_pattern $cdc_text]} {
        error "CDC warning ID/count changed: $expected_cdc_pattern"
    }
}
catch {
    check_timing -verbose \
        -file [file join $result_dir check_timing_routed.rpt]
}
catch {
    report_exceptions -coverage \
        -file [file join $result_dir exceptions_coverage_routed.rpt]
}
catch {
    report_exceptions -ignored \
        -file [file join $result_dir exceptions_ignored_routed.rpt]
}
catch {
    report_bus_skew \
        -file [file join $result_dir bus_skew_routed.rpt]
}
report_timing -from $mode_shadow_cells -to $audio_mode_cells \
    -delay_type max -max_paths 4 \
    -file [file join $result_dir mode_absolute_delay_routed.rpt]
set mode_delay_paths [get_timing_paths -from $mode_shadow_cells \
    -to $audio_mode_cells -delay_type max -max_paths 4]
if {[llength $mode_delay_paths] != 4} {
    error "Expected four family/bit bundled-data max-delay paths"
}
foreach mode_delay_path $mode_delay_paths {
    set mode_delay_slack [get_property SLACK $mode_delay_path]
    if {$mode_delay_slack < 0.0 || $mode_delay_slack > 50.0} {
        error "Bundled-data absolute max-delay is failed or overridden: slack=$mode_delay_slack"
    }
}

write_primitive_report \
    [file join $result_dir dsp_utilization_routed.rpt] \
    "DSP48*" "National-finals DSP utilization"
write_primitive_report \
    [file join $result_dir bram_utilization_routed.rpt] \
    "RAMB*" "National-finals BRAM utilization"
write_primitive_report \
    [file join $result_dir mmcm_utilization_routed.rpt] \
    "MMCME2*" "National-finals MMCM utilization"

set total_dsp_count [llength [get_cells -hierarchical \
    -filter {REF_NAME =~ DSP48*}]]
set cic_integrator_dsp_count [expr {$total_dsp_count - 2}]
if {$cic_integrator_dsp_count < 0 || $cic_integrator_dsp_count > 2} {
    error "Unexpected DSP mapping: total DSP count is $total_dsp_count"
}
if {$cic_integrator_dsp_count == 2} {
    set cic_mapping_description \
        "both high-rate integrators use DSP48E1"
} elseif {$cic_integrator_dsp_count == 1} {
    set cic_mapping_description \
        "the 26-bit first integrator uses LUT CARRY4 and the 29-bit final integrator uses DSP48E1"
} else {
    set cic_mapping_description \
        "both high-rate integrators use LUT CARRY4"
}

set manifest_handle [open [file join $result_dir build_manifest.txt] w]
puts $manifest_handle "National-finals dual-rate board build"
puts $manifest_handle "Synthesis checkpoint: $synth_dcp"
puts $manifest_handle "Part: [get_property PART [current_design]]"
puts $manifest_handle "Top: board_demo_competition_dac8_top"
puts $manifest_handle "Bitstream: $bitstream_dst"
puts $manifest_handle [format "Routed setup slack: %.3f ns" $setup_slack]
puts $manifest_handle [format "Routed hold slack: %.3f ns" $hold_slack]
set dac_setup_path [get_timing_paths -to [get_ports {dac_data[*]}] \
    -delay_type max -max_paths 1]
set dac_hold_path [get_timing_paths -to [get_ports {dac_data[*]}] \
    -delay_type min -max_paths 1]
puts $manifest_handle [format "AD9708 output setup slack: %.3f ns" \
    [get_property SLACK $dac_setup_path]]
puts $manifest_handle [format "AD9708 output hold slack: %.3f ns" \
    [get_property SLACK $dac_hold_path]]
puts $manifest_handle "44.1-kHz family 128x clock: 5.644796 MHz (-0.64 ppm nominal)"
puts $manifest_handle "48-kHz family 128x clock: 6.144068 MHz (+11.03 ppm nominal)"
puts $manifest_handle "Bundled-data CDC: mode_shadow\[1:0\] has 50.000 ns relative bus-skew and absolute datapath-delay requirements; verify routed evidence in bus_skew_routed.rpt, mode_absolute_delay_routed.rpt, and exceptions_ignored_routed.rpt"
if {$p3_joint_stage3 != 0} {
    puts $manifest_handle "Architecture: 1-DSP Stage1 + 1-DSP shared Stage2/3 with mode-specific coefficient banks + exact N3 Hold CIC16 with $cic_integrator_dsp_count DSP integrator(s)"
    puts $manifest_handle "P3 equalizer fold: the 128x compensation response is folded into Stage3; 4x/8x retain the flat Stage3 bank and the separate shift-add equalizer is not elaborated"
} else {
    puts $manifest_handle "Architecture: 1-DSP Stage1 + 1-DSP shared Stage2/3 + shift-add equalizer + exact N3 Hold CIC16 with $cic_integrator_dsp_count DSP integrator(s)"
    puts $manifest_handle "Equalizer optimization: combinational hand-off plus lossless 21-bit headroom removes the intermediate 20-bit saturation mux; the CIC final quantizer remains 20-bit"
}
puts $manifest_handle "N3 Hold optimization: C^3 -> up16 -> I^3 is rewritten exactly as C^2 -> Hold16 -> I^2; proven 26-bit first and 29-bit final integrator widths replace the former conservative 33-bit states"
puts $manifest_handle "CIC mapping: two low-rate comb stages use LUT CARRY4; $cic_mapping_description"
puts $manifest_handle "Stage1 optimization: DSP48E1 A+D preadder plus multiplier/PREG MAC state, 41-bit proven bound, and exact DSP-resident Q15 rounding"
puts $manifest_handle "Stage2/3 optimization: shared DSP48E1 PREG MAC state, constant 16383 plus CARRYIN exact rounding, and board-only elimination of the unreachable aligned-CE pending-history queue"
puts $manifest_handle "Stage3 correctness: true Q15 coefficients, complete 38-bit MAC view, and explicit signed 20/21-bit saturation selected by architecture"
puts $manifest_handle "Stage2/3 correctness: job head/fill snapshots protect an active MAC from the next ring-buffer write"
puts $manifest_handle "Synthesis directive: $expected_synth_directive"
puts $manifest_handle "Synthesis flatten hierarchy: $expected_flatten_hierarchy"
puts $manifest_handle "Synthesis resource sharing: $expected_resource_sharing"
puts $manifest_handle "Stage1 DSP48 preadder: $expected_stage1_dsp48_preadder"
puts $manifest_handle "Requested CIC integrator DSP mode: $expected_cic_integrator_dsp_mode"
puts $manifest_handle "Stage1 single-BRAM history mode: $expected_stage1_single_bram"
puts $manifest_handle "Stage2/3 unified-BRAM history mode: $expected_stage23_unified_bram"
puts $manifest_handle "Implementation opt directive: $implementation_opt_directive"
puts $manifest_handle "P3 joint Stage3 mode: $p3_joint_stage3"
close $manifest_handle

puts "NATIONAL_FINALS_SINGLE_PROCESS_BUILD_PASS"
puts [format "SETUP_SLACK_NS=%.3f" $setup_slack]
puts [format "HOLD_SLACK_NS=%.3f" $hold_slack]
puts "RESULT_DIR=$result_dir"
puts "BITSTREAM=$bitstream_dst"
close_design
