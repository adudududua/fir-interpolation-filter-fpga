set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set result_dir [expr {$argc > 0 ? [file normalize [lindex $argv 0]] : [file join $script_dir results latest]}]
set jobs [expr {$argc > 1 ? [lindex $argv 1] : 1}]
set core_variant [expr {$argc > 2 ? [lindex $argv 2] : "baseline"}]
set top_name interp128_all2x_v7_folded_fir_cic_top_ce
set part_name xc7a35tfgg484-2
file mkdir $result_dir

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

require_condition [expr {$core_variant eq "baseline" ||
                         $core_variant eq "sequential_pair" ||
                         $core_variant eq "wordlength_24_20_20"}] \
    "core variant must be baseline, sequential_pair, or wordlength_24_20_20"
set stage2_data_w [expr {$core_variant eq "wordlength_24_20_20" ? 20 : 22}]

# A damaged user Tcl Store must not stop the competition report. Vivado sets
# XILINX_VIVADO to its own installation root, so this fallback is portable
# across installation drives and does not modify user preferences.
if {[info exists ::env(XILINX_VIVADO)]} {
    set tcl_store [file join $::env(XILINX_VIVADO) data XilinxTclStore]
    set appinit_dir [file join $tcl_store support appinit]
    set xilinx_apps_dir [file join $tcl_store tclapp xilinx]
    if {[file isdirectory $appinit_dir] && [lsearch -exact $::auto_path $appinit_dir] == -1} {
        lappend ::auto_path $appinit_dir
    }
    foreach app_dir [glob -nocomplain -types d -directory $xilinx_apps_dir *] {
        if {[lsearch -exact $::auto_path $app_dir] == -1} {
            lappend ::auto_path $app_dir
        }
    }
    catch {package require ::tclapp::support::appinit 1.2}
}

set include_dirs [list \
    [file join $source_root all2x_v2] \
    [file join $source_root all2x_v3] \
    [file join $source_root all2x_v4] \
    [file join $source_root all2x_v5] \
    [file join $source_root all2x_v6] \
    [file join $source_root all2x_v7]]

# This is the signed-off synthesis source manifest. Reading the RTL directly
# keeps the board project read-only and prevents a Top change in the GUI.
set relative_sources [list \
    audio_pcm_rom_source.v \
    all2x_v2/bridge_valid_only_to_interp2_ce.v \
    all2x_v6/bridge_valid_quantized_to_interp2_ce.v \
    national_finals/cic3_compensator_shiftadd_ce.v \
    all2x_v7/cic_interp16_core_dsp_ce.v \
    national_finals/cic_interp16_n3_hold2_dsp_ce.v \
    national_finals/cic_interp16_serial_comb_dsp_ce.v \
    demo_interp_dac8_audio_pcm_common.v \
    national_finals/dual_family_audio_clock.v \
    national_finals/dual_rate_test_tone_rom_source.v \
    fir_core_symm_interp2_all2x.v \
    fir_core_symm_interp2_stage1_mac.v \
    all2x_v6/interp128_all2x_v6_mixed_width_top_ce.v \
    all2x_v7/interp128_all2x_v7_folded_fir_cic_top_ce.v \
    all2x_v2/interp2_all2x_v2_stage_select.v \
    interp2_ctrl_ce.v \
    all2x_v2/interp2_halfband7_shiftadd_ce.v \
    national_finals/interp2_stage1_single_bram_serial_ce.v \
    all2x_v3/interp2_stage1_strict_halfband_bram_ce.v \
    all2x_v7/interp2_stage23_folded_cic_dsp_ce.v \
    all2x_v7/interp2_stage23_lutram_cic_dsp_ce.v \
    all2x_v4/interp2_stage23_shared_dsp_ce.v \
    interp2_top_symm_ce_all2x.v \
    matrix_keypad_mode_ctrl_compact.v \
    national_finals/matrix_keypad_mode_ctrl_ultracompact.v \
    national_finals/nf_mode_cdc_handshake.v \
    national_finals/nf_stage1_history_ramb18_sdp.v \
    national_finals/nf_stage23_history_ramb18_sdp.v \
    national_finals/nf_unified_fir_coeff_bram.v \
    all2x_v5/round_sat_q15_compact_to24.v \
    round_sat_q16_to24.v \
    all2x_v6/round_sat_shift_compact.v \
    board_demo_competition_dac8_top.v]

set sources {}
foreach relative_source $relative_sources {
    if {$core_variant eq "sequential_pair" &&
        $relative_source eq "national_finals/cic_interp16_n3_hold2_dsp_ce.v"} {
        continue
    }
    set source_file [file join $source_root $relative_source]
    require_condition [file exists $source_file] "Missing RTL source: $source_file"
    lappend sources $source_file
}
if {$core_variant eq "sequential_pair"} {
    set experiment_dir [file normalize [file join $script_dir .. structure_experiments]]
    lappend sources \
        [file join $experiment_dir cic_interp16_n3_hold2_two24_sequential_pair_ce.v] \
        [file join $experiment_dir cic_sequential_pair_dropin_adapter.v]
}
read_verilog $sources

set core_generics [list \
    STAGE1_ACC_W=41 \
    STAGE23_ACC_W=38 \
    STAGE2_DATA_W=$stage2_data_w \
    CIC_ORDER=3 \
    FINAL_PRUNE_LSB=0 \
    USE_LUTRAM_STAGE23=1 \
    STAGE3_FLAT=1 \
    USE_CIC3_SHIFTADD_COMPENSATOR=0 \
    USE_BRAM_STAGE23_HISTORY=1 \
    USE_UNIFIED_BRAM_STAGE23_HISTORY=1 \
    USE_SINGLE_BRAM_STAGE1=1 \
    USE_BRAM_STAGE23_COEFF=1 \
    USE_PACKED_BRAM_STAGE23=0 \
    CIC_BURST_COUNTER_USE_DSP=0 \
    CIC_COMB_USE_DSP=0 \
    USE_SERIAL_CIC_COMB=1 \
    USE_N3_HOLD_EQUIV=1 \
    USE_STAGE1_DSP48_PREADDER=1 \
    USE_NATIONAL_FINALS_NARROW_STAGE23=1 \
    USE_P3_JOINT_STAGE3=1 \
    ASSUME_ALIGNED_POW2_CE=1 \
    CIC_INTEGRATOR_DSP_MODE=2 \
    USE_UNIFIED_FIR_COEFF_BRAM=1]

set_param general.maxThreads $jobs
set synth_command [list synth_design \
    -top $top_name \
    -part $part_name \
    -mode out_of_context \
    -include_dirs $include_dirs \
    -flatten_hierarchy full \
    -directive AreaOptimized_high \
    -resource_sharing on \
    -shreg_min_size 5]
foreach generic_value $core_generics {
    lappend synth_command -generic $generic_value
}
{*}$synth_command

create_clock -name core_clk_6m144 -period 162.760 \
    -waveform {0.000 81.380} [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y16 [get_ports clk]
set_false_path -from [get_ports rst_n]

# Keep zero-delay OOC boundaries for the signed-off 193-LUT placement result.
# Those artificial boundary paths are reported, but the pass/fail timing gate
# below is calculated separately over internal register-to-register paths.
set core_data_inputs [get_ports {ce2 ce4 ce8 ce16 ce32 ce64 ce128 \
    x_in x_in_valid stage3_compensated_mode}]
set_input_delay -clock [get_clocks core_clk_6m144] 0.000 $core_data_inputs
set_output_delay -clock [get_clocks core_clk_6m144] 0.000 [all_outputs]

report_utilization -file [file join $result_dir utilization_post_synth.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir timing_post_synth.rpt]
write_checkpoint -force [file join $result_dir core_post_synth.dcp]

opt_design -directive ExploreArea
place_design -directive Explore
route_design

set utilization_report [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_post_route.rpt]
report_utilization -hierarchical -hierarchical_min_primitive_count 0 \
    -file [file join $result_dir utilization_post_route_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir timing_post_route_with_ooc_boundaries.rpt]
report_route_status -file [file join $result_dir route_status_post_route.rpt]
report_drc -file [file join $result_dir drc_post_route.rpt]
check_timing -verbose -file [file join $result_dir check_timing_post_route.rpt]
write_checkpoint -force [file join $result_dir core_post_route.dcp]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused lut_count] \
    "Could not parse Slice LUT count."
require_condition \
    [regexp {\|\s*LUT as Memory[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused lutram_count] \
    "Could not parse LUTRAM count."
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused ff_count] \
    "Could not parse Slice Register count."

set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set bram36_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]]
set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]]
set internal_registers [all_registers -clock [get_clocks core_clk_6m144]]
require_condition [expr {[llength $internal_registers] > 0}] "No internal registers found."
set internal_setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 \
    -from $internal_registers -to $internal_registers]
set internal_hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 \
    -from $internal_registers -to $internal_registers]
require_condition [expr {[llength $internal_setup_path] == 1}] "No internal setup path found."
require_condition [expr {[llength $internal_hold_path] == 1}] "No internal hold path found."
set internal_wns [get_property SLACK $internal_setup_path]
set internal_whs [get_property SLACK $internal_hold_path]
report_timing -delay_type max -max_paths 20 -nworst 1 \
    -from $internal_registers -to $internal_registers \
    -file [file join $result_dir timing_internal_setup.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 \
    -from $internal_registers -to $internal_registers \
    -file [file join $result_dir timing_internal_hold.rpt]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

set summary_fid [open [file join $result_dir core_ooc_summary.txt] w]
puts $summary_fid "TOOL=Vivado 2025.2"
puts $summary_fid "VARIANT=$core_variant"
puts $summary_fid "STAGE2_DATA_W=$stage2_data_w"
puts $summary_fid "TOP=$top_name"
puts $summary_fid "PART=$part_name"
puts $summary_fid "CLOCK_MHZ=6.144"
puts $summary_fid "TIMING_SCOPE=INTERNAL_REGISTER_TO_REGISTER"
puts $summary_fid "POST_ROUTE_LUT=$lut_count"
puts $summary_fid "POST_ROUTE_LUTRAM=$lutram_count"
puts $summary_fid "POST_ROUTE_FF=$ff_count"
puts $summary_fid "POST_ROUTE_DSP48E1=$dsp_count"
puts $summary_fid "POST_ROUTE_RAMB18E1=$bram18_count"
puts $summary_fid "POST_ROUTE_RAMB36E1=$bram36_count"
puts $summary_fid "POST_ROUTE_BRAM_TILE=[expr {$bram36_count + 0.5 * $bram18_count}]"
puts $summary_fid "POST_ROUTE_MMCM=$mmcm_count"
puts $summary_fid "INTERNAL_WNS_NS=$internal_wns"
puts $summary_fid "INTERNAL_WHS_NS=$internal_whs"
puts $summary_fid "POST_ROUTE_DRC_ERRORS=[llength $drc_errors]"
close $summary_fid

puts "CORE_OOC_LUT=$lut_count"
puts "CORE_OOC_FF=$ff_count"
puts "CORE_OOC_DSP=$dsp_count"
puts "CORE_OOC_RAMB18=$bram18_count"
puts "CORE_OOC_INTERNAL_WNS=$internal_wns"
puts "CORE_OOC_INTERNAL_WHS=$internal_whs"
puts "CORE_OOC_DRC_ERRORS=[llength $drc_errors]"

if {$core_variant eq "baseline"} {
    require_condition [expr {$lut_count == 193}] \
        "Expected exactly 193 LUT for the signed-off Vivado 2025.2 OOC flow; got $lut_count."
    require_condition [expr {$ff_count == 281}] "Expected exactly 281 FF; got $ff_count."
} else {
    require_condition [expr {$lut_count < 193}] \
        "Experimental core did not improve the 193-LUT baseline; got $lut_count."
}
require_condition [expr {$lutram_count == 0}] "Expected 0 LUTRAM; got $lutram_count."
require_condition [expr {$dsp_count == 4}] "Expected exactly 4 DSP48E1; got $dsp_count."
require_condition [expr {$bram18_count == 3 && $bram36_count == 0}] \
    "Expected 3 RAMB18E1 and 0 RAMB36E1."
require_condition [expr {$mmcm_count == 0}] "OOC core must contain 0 MMCM."
require_condition [expr {$internal_wns >= 0.0}] \
    "Internal setup timing failed: WNS=$internal_wns ns."
require_condition [expr {$internal_whs >= 0.0}] \
    "Internal hold timing failed: WHS=$internal_whs ns."
require_condition [expr {[llength $drc_errors] == 0}] \
    "OOC DRC contains [llength $drc_errors] error(s)."

puts "CORE_OOC_2025_2_PASS"
close_design
exit
