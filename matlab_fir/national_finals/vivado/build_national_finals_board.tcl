# National-finals board build for XC7A35T / Vivado 2018.3.
#
# The script updates the existing project with the national-finals sources,
# keeps the resource-minimized Phase-7 configuration, runs area-optimized
# synthesis/implementation, writes a bitstream, and exports acceptance reports
# without overwriting the regionals result directory.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set src_dir [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set nf_src_dir [file join $src_dir national_finals]
set sim_dir [file join $project_dir XC7A35T_interp.srcs sim_1 new]
set nf_sim_dir [file join $sim_dir national_finals]
set reuse_current_synthesis 0
set synthesis_only 0
set synth_directive AreaOptimized_high
set flatten_hierarchy full
set resource_sharing on
set result_tag board_dual_rate_cic6_round7_headroom_opt
set stage1_dsp48_preadder 1
set cic_integrator_dsp_mode 2
set p3_joint_stage3 1
set stage1_single_bram 1
set stage23_unified_bram 1
if {$argc > 0} {
    set reuse_current_synthesis [lindex $argv 0]
}
if {$argc > 1} {
    set synthesis_only [lindex $argv 1]
}
if {$argc > 2} {
    set synth_directive [lindex $argv 2]
}
if {$argc > 3} {
    set flatten_hierarchy [lindex $argv 3]
}
if {$argc > 4} {
    set resource_sharing [lindex $argv 4]
}
if {$argc > 5} {
    set result_tag [lindex $argv 5]
}
if {$argc > 6} {
    set stage1_dsp48_preadder [lindex $argv 6]
}
if {$argc > 7} {
    set cic_integrator_dsp_mode [lindex $argv 7]
}
if {$argc > 8} {
    set p3_joint_stage3 [lindex $argv 8]
}
if {$argc > 9} {
    set stage1_single_bram [lindex $argv 9]
}
if {$argc > 10} {
    set stage23_unified_bram [lindex $argv 10]
}
if {$reuse_current_synthesis != 0 && $reuse_current_synthesis != 1} {
    error "reuse_current_synthesis must be 0 or 1"
}
if {$synthesis_only != 0 && $synthesis_only != 1} {
    error "synthesis_only must be 0 or 1"
}
if {$stage1_dsp48_preadder != 0 && $stage1_dsp48_preadder != 1} {
    error "stage1_dsp48_preadder must be 0 or 1"
}
if {$cic_integrator_dsp_mode < 0 || $cic_integrator_dsp_mode > 2} {
    error "cic_integrator_dsp_mode must be 0, 1, or 2"
}
if {$p3_joint_stage3 != 0 && $p3_joint_stage3 != 1} {
    error "p3_joint_stage3 must be 0 or 1"
}
if {$stage1_single_bram != 0 && $stage1_single_bram != 1} {
    error "stage1_single_bram must be 0 or 1"
}
if {$stage23_unified_bram != 0 && $stage23_unified_bram != 1} {
    error "stage23_unified_bram must be 0 or 1"
}
if {![regexp {^[A-Za-z0-9_-]+$} $result_tag]} {
    error "result_tag may contain only letters, digits, underscore, and dash"
}
set result_dir [file normalize [file join $script_dir .. vivado_results $result_tag]]

set nf_sources [list \
    [file join $nf_src_dir nf_signedoff_filter_core.v] \
    [file join $nf_src_dir nf_unified_fir_coeff_bram.v] \
    [file join $nf_src_dir nf_stage1_history_ramb18_sdp.v] \
    [file join $nf_src_dir interp2_stage1_single_bram_serial_ce.v] \
    [file join $nf_src_dir nf_stage23_history_ramb18_sdp.v] \
    [file join $nf_src_dir cic3_compensator_shiftadd_ce.v] \
    [file join $nf_src_dir cic_interp16_serial_comb_dsp_ce.v] \
    [file join $nf_src_dir cic_interp16_n3_hold2_dsp_ce.v] \
    [file join $nf_src_dir dual_family_audio_clock.v] \
    [file join $nf_src_dir nf_mode_cdc_handshake.v] \
    [file join $nf_src_dir dual_rate_test_tone_rom_source.v] \
    [file join $nf_src_dir matrix_keypad_mode_ctrl_ultracompact.v] \
    [file join $nf_src_dir nf_sine_15k_dual_rate_24bit_256.mem] \
    [file join $nf_src_dir nf_sine_15k_dual_rate_packed32_256.mem]]

set nf_sim_sources [list \
    [file join $nf_sim_dir tb_cic3_compensator_shiftadd_ce.v] \
    [file join $nf_sim_dir tb_dual_family_audio_clock.v]]

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

require_file $project_file
foreach source_file [concat $nf_sources $nf_sim_sources] {
    require_file $source_file
}
file mkdir $result_dir

open_project $project_file

foreach source_file $nf_sources {
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
    }
}
set mem_file [file join $nf_src_dir nf_sine_15k_dual_rate_24bit_256.mem]
set_property file_type {Memory Initialization Files} [get_files $mem_file]
set packed_mem_file [file join $nf_src_dir \
    nf_sine_15k_dual_rate_packed32_256.mem]
set_property file_type {Memory Initialization Files} [get_files $packed_mem_file]

foreach source_file $nf_sim_sources {
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset sim_1 -norecurse $source_file
    }
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
set_property generic [list \
    USE_PHASE7_LUTRAM_STAGE23=1 \
    USE_COMPACT_KEYPAD=1 \
    USE_ULTRACOMPACT_KEYPAD=1 \
    COMPACT_KEYPAD_SCAN_DIV=20000 \
    USE_SHARED_KEYPAD_SCAN_TICK=1 \
    USE_PHASE7_BRAM_STAGE23_HISTORY=1 \
    USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY=$stage23_unified_bram \
    USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1=$stage1_single_bram \
    USE_PHASE7_BRAM_STAGE23_COEFF=1 \
    USE_PHASE8_PACKED_BRAM_STAGE23=0 \
    USE_PHASE7_CIC_BURST_COUNTER_DSP=0 \
    USE_NATIONAL_FINALS_DATAPATH=1 \
    USE_NATIONAL_FINALS_SERIAL_CIC_COMB=1 \
    USE_NATIONAL_FINALS_N3_HOLD_EQUIV=1 \
    USE_NATIONAL_FINALS_CIC_COMB_DSP=0 \
    USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER=$stage1_dsp48_preadder \
    USE_NATIONAL_FINALS_NARROW_STAGE23=1 \
    USE_NATIONAL_FINALS_P3_JOINT_STAGE3=$p3_joint_stage3 \
    USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=$cic_integrator_dsp_mode] \
    [get_filesets sources_1]

# Keep the GUI simulation topology identical to the signed-off command-line
# full-chain regression.  Without these defines sim_1 silently selects older
# Phase-7 branches even though synthesis uses the national-finals generics.
set_property top tb_phase7_full_chain_bittrue [get_filesets sim_1]
set_property verilog_define [list] [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $synth_directive \
    [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $flatten_hierarchy \
    [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING $resource_sharing \
    [get_runs synth_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]

reset_run impl_1
if {$reuse_current_synthesis == 0} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
        error "National-finals synthesis did not complete."
    }
} elseif {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Requested synthesis reuse, but synth_1 is not complete."
}

# Record the exact profile which produced synth_1.  The low-memory
# implementation flow refuses to reuse a checkpoint with a different profile.
set synth_provenance_file [file join $project_dir XC7A35T_interp.runs synth_1 \
    national_finals_synth_provenance.txt]
set synth_provenance_handle [open $synth_provenance_file w]
puts $synth_provenance_handle "synth_directive=$synth_directive"
puts $synth_provenance_handle "flatten_hierarchy=$flatten_hierarchy"
puts $synth_provenance_handle "resource_sharing=$resource_sharing"
puts $synth_provenance_handle "stage1_dsp48_preadder=$stage1_dsp48_preadder"
puts $synth_provenance_handle "cic_integrator_dsp_mode=$cic_integrator_dsp_mode"
puts $synth_provenance_handle "p3_joint_stage3=$p3_joint_stage3"
puts $synth_provenance_handle "stage1_single_bram=$stage1_single_bram"
puts $synth_provenance_handle "stage23_unified_bram=$stage23_unified_bram"
close $synth_provenance_handle

if {$synthesis_only != 0} {
    open_run synth_1
    set source_manifest_handle [open \
        [file join $result_dir synthesis_sources.txt] w]
    foreach source_file [get_files -compile_order sources \
            -used_in synthesis] {
        puts $source_manifest_handle [file normalize $source_file]
    }
    foreach constraint_file [get_files -of_objects [get_filesets constrs_1]] {
        puts $source_manifest_handle [file normalize $constraint_file]
    }
    close $source_manifest_handle
    report_utilization \
        -file [file join $result_dir utilization_synthesized.rpt]
    report_utilization -hierarchical \
        -file [file join $result_dir utilization_hierarchical_synthesized.rpt]
    write_primitive_report \
        [file join $result_dir dsp_utilization_synthesized.rpt] \
        "DSP48*" "National-finals synthesized DSP utilization"
    write_primitive_report \
        [file join $result_dir bram_utilization_synthesized.rpt] \
        "RAMB*" "National-finals synthesized BRAM utilization"
    close_design
    puts "NATIONAL_FINALS_SYNTHESIS_PASS"
    close_project
    return
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "National-finals implementation did not complete."
}

open_run impl_1
report_utilization -file [file join $result_dir utilization_placed.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 30 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $result_dir clock_interaction_routed.rpt]
report_power -file [file join $result_dir power_vectorless_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
catch {
    report_methodology \
        -file [file join $result_dir methodology_routed.rpt]
}
catch {
    report_cdc -details -file [file join $result_dir cdc_routed.rpt]
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

write_checkpoint -force \
    [file join $result_dir national_finals_board_routed.dcp]

set bitstream_src [file join $project_dir XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "National-finals bitstream was not generated."
}
set bitstream_dst [file join $result_dir \
    national_finals_dual_rate_4x8x128x_areaopt.bit]
file copy -force $bitstream_src $bitstream_dst

set manifest_handle [open [file join $result_dir build_manifest.txt] w]
puts $manifest_handle "National-finals dual-rate board build"
puts $manifest_handle "Project: $project_file"
puts $manifest_handle "Part: [get_property PART [current_project]]"
puts $manifest_handle "Top: board_demo_competition_dac8_top"
puts $manifest_handle "Bitstream: $bitstream_dst"
puts $manifest_handle "44.1-kHz family 128x clock: 5.644796 MHz (-0.64 ppm nominal)"
puts $manifest_handle "48-kHz family 128x clock: 6.144068 MHz (+11.03 ppm nominal)"
if {$p3_joint_stage3 != 0} {
    puts $manifest_handle "Architecture: shared 2x/2x/2x FIR with mode-specific flat/compensated Stage3 coefficient banks + exact N3 Hold CIC16 with two DSP integrators"
    puts $manifest_handle "P3 equalizer fold: the 128x compensation response is folded into Stage3; 4x/8x retain the flat Stage3 bank and the separate shift-add equalizer is not elaborated"
} else {
    puts $manifest_handle "Architecture: shared 2x/2x/2x FIR + shift-add CIC equalizer + exact N3 Hold CIC16 with two DSP integrators"
    puts $manifest_handle "Equalizer headroom optimization: lossless 21-bit equalizer output feeds a 21-bit CIC input; clipping is deferred to the final 20-bit CIC quantizer"
}
puts $manifest_handle "CIC DSP mapping: two low-rate combs use LUT CARRY4; exact Hold16 feeds two high-rate DSP48E1 integrators"
puts $manifest_handle "Synthesis directive: $synth_directive"
puts $manifest_handle "Synthesis flatten hierarchy: $flatten_hierarchy"
puts $manifest_handle "Synthesis resource sharing: $resource_sharing"
puts $manifest_handle "Stage1 DSP48 preadder: $stage1_dsp48_preadder"
puts $manifest_handle "CIC integrator DSP mode: $cic_integrator_dsp_mode"
puts $manifest_handle "P3 joint Stage3 mode: $p3_joint_stage3"
puts $manifest_handle "Stage1 single-BRAM history mode: $stage1_single_bram"
puts $manifest_handle "Stage2/3 unified-BRAM history mode: $stage23_unified_bram"
puts $manifest_handle "Rounding: constant 16383 plus DSP48 CARRYIN for non-negative MAC sums"
puts $manifest_handle "Stage3: complete 38-bit MAC view with explicit signed output saturation"
puts $manifest_handle "Implementation opt directive: Default"
close $manifest_handle

puts "NATIONAL_FINALS_BOARD_BUILD_PASS"
puts "RESULT_DIR=$result_dir"
puts "BITSTREAM=$bitstream_dst"
close_project
