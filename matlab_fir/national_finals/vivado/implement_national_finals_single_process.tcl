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
set distributed_coeff_rom_mode 0
if {$argc > 0} {
    set result_tag [lindex $argv 0]
}
if {$argc > 1} {
    set implementation_opt_directive [lindex $argv 1]
}
if {$argc > 2} {
    set distributed_coeff_rom_mode [lindex $argv 2]
}
if {![regexp {^[A-Za-z0-9_-]+$} $result_tag]} {
    error "result_tag may contain only letters, digits, underscore, and dash"
}
if {$implementation_opt_directive ni \
    {Default Explore ExploreWithRemap ExploreArea AddRemap}} {
    error "Unsupported implementation opt directive: $implementation_opt_directive"
}
if {$distributed_coeff_rom_mode < 0 || $distributed_coeff_rom_mode > 2} {
    error "distributed_coeff_rom_mode must be 0, 1, or 2"
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
catch {
    report_methodology \
        -file [file join $result_dir methodology_routed.rpt]
}
catch {
    report_cdc -details -file [file join $result_dir cdc_routed.rpt]
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
    report_bus_skew \
        -file [file join $result_dir bus_skew_routed.rpt]
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
puts $manifest_handle "Bundled-data CDC: mode_shadow\[1:0\] has a 50.000 ns set_bus_skew requirement; verify actual routed skew in bus_skew_routed.rpt"
puts $manifest_handle "Architecture: 1-DSP Stage1 + 1-DSP shared Stage2/3 + shift-add equalizer + exact N3 Hold CIC16 with $cic_integrator_dsp_count DSP integrator(s)"
puts $manifest_handle "Memory optimization: board PCM ROM and Stage1 history share one RAMB18E1 read port; Stage1 reads have priority and PCM requests are held until the verified idle window"
puts $manifest_handle "Coefficient memory: mode $distributed_coeff_rom_mode (0=unified RAMB18, 1=dual distributed ROM with registered addresses, 2=dual distributed ROM with registered outputs)"
puts $manifest_handle "N3 Hold optimization: C^3 -> up16 -> I^3 is rewritten exactly as C^2 -> Hold16 -> I^2; proven 26-bit first and 29-bit final integrator widths replace the former conservative 33-bit states"
puts $manifest_handle "Equalizer optimization: combinational hand-off plus lossless 21-bit headroom removes the intermediate 20-bit saturation mux; the CIC final quantizer remains 20-bit"
puts $manifest_handle "CIC mapping: two low-rate comb stages use LUT CARRY4; $cic_mapping_description"
puts $manifest_handle "Stage1 optimization: DSP48E1 A+D preadder plus multiplier/PREG MAC state, 41-bit proven bound, and exact DSP-resident Q15 rounding"
puts $manifest_handle "Stage2/3 optimization: shared DSP48E1 PREG MAC state, constant 16383 plus CARRYIN exact rounding, and board-only elimination of the unreachable aligned-CE pending-history queue"
puts $manifest_handle "Stage3 correctness: true Q15 coefficients, complete 38-bit MAC view, and explicit signed 20-bit saturation"
puts $manifest_handle "Stage2/3 correctness: job head/fill snapshots protect an active MAC from the next ring-buffer write"
puts $manifest_handle "Synthesis directive: AreaOptimized_high"
puts $manifest_handle "Synthesis resource sharing: on"
puts $manifest_handle "Implementation opt directive: $implementation_opt_directive"
close $manifest_handle

puts "NATIONAL_FINALS_SINGLE_PROCESS_BUILD_PASS"
puts [format "SETUP_SLACK_NS=%.3f" $setup_slack]
puts [format "HOLD_SLACK_NS=%.3f" $hold_slack]
puts "RESULT_DIR=$result_dir"
puts "BITSTREAM=$bitstream_dst"
close_design
