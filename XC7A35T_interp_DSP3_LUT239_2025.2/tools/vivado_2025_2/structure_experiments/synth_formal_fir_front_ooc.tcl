set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set flatten_mode [expr {$argc > 0 ? [lindex $argv 0] : "full"}]
set stage2_data_w [expr {$argc > 1 ? [lindex $argv 1] : 22}]
if {$stage2_data_w != 22 && $stage2_data_w != 20} {
    error "Stage2 data width must be 22 or 20"
}
set work_dir [file normalize [file join $script_dir .. _work post221_4dsp_2bram wordlength_24_${stage2_data_w}_20 fir_front_ooc_$flatten_mode]]
file mkdir $work_dir

set include_dirs [list \
    [file join $source_root all2x_v2] \
    [file join $source_root all2x_v3] \
    [file join $source_root all2x_v4] \
    [file join $source_root all2x_v5] \
    [file join $source_root all2x_v6] \
    [file join $source_root all2x_v7]]

set sources [list \
    [file join $source_root all2x_v6 bridge_valid_quantized_to_interp2_ce.v] \
    [file join $source_root all2x_v6 round_sat_shift_compact.v] \
    [file join $source_root all2x_v7 interp128_all2x_v7_folded_fir_cic_top_ce.v] \
    [file join $source_root all2x_v7 interp2_stage23_lutram_cic_dsp_ce.v] \
    [file join $source_root national_finals interp2_stage1_single_bram_serial_ce.v] \
    [file join $source_root national_finals nf_stage1_history_ramb18_sdp.v] \
    [file join $source_root national_finals nf_stage23_history_ramb18_sdp.v] \
    [file join $source_root national_finals nf_unified_fir_coeff_bram.v] \
    [file join $source_root national_finals cic_interp16_n3_hold2_dsp_ce.v] \
    [file join $script_dir formal_fir_front_ooc_wrapper.v]]

read_verilog $sources
synth_design -top formal_fir_front_ooc_wrapper \
    -part xc7a35tfgg484-2 -mode out_of_context \
    -generic STAGE2_DATA_W=$stage2_data_w \
    -include_dirs $include_dirs -flatten_hierarchy $flatten_mode \
    -directive AreaOptimized_high -resource_sharing on -shreg_min_size 5
create_clock -name fir_clk_6m144 -period 162.760 [get_ports clk]

set utilization [report_utilization -return_string]
report_utilization -file [file join $work_dir utilization_post_synth.rpt]
report_utilization -hierarchical -hierarchical_min_primitive_count 0 \
    -file [file join $work_dir utilization_hierarchical_post_synth.rpt]
write_checkpoint -force [file join $work_dir post_synth.dcp]

regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} $utilization unused lut_count
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} $utilization unused ff_count
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set fid [open [file join $work_dir result.txt] w]
puts $fid "STAGE=POST_SYNTH"
puts $fid "STAGE2_DATA_W=$stage2_data_w"
puts $fid "LUT=$lut_count"
puts $fid "FF=$ff_count"
puts $fid "DSP48E1=$dsp_count"
puts $fid "RAMB18E1=$bram18_count"
close $fid
puts "FORMAL_FIR_FRONT_LUT=$lut_count"
puts "FORMAL_FIR_FRONT_STAGE2_DATA_W=$stage2_data_w"
puts "FORMAL_FIR_FRONT_FF=$ff_count"
puts "FORMAL_FIR_FRONT_DSP=$dsp_count"
puts "FORMAL_FIR_FRONT_RAMB18=$bram18_count"
