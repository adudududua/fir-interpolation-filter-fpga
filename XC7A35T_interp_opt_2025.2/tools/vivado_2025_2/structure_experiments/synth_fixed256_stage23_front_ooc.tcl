set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set flatten_mode [expr {$argc > 0 ? [lindex $argv 0] : "full"}]
set synth_directive [expr {$argc > 1 ? [lindex $argv 1] : "AreaOptimized_high"}]
set work_dir [file normalize [file join $script_dir .. _work structure_redesign fixed256_stage23_front_ooc_${flatten_mode}_${synth_directive}]]
file mkdir $work_dir
set include_dirs [list \
    [file join $source_root all2x_v2] [file join $source_root all2x_v3] \
    [file join $source_root all2x_v4] [file join $source_root all2x_v5] \
    [file join $source_root all2x_v6] [file join $source_root all2x_v7]]
set sources [list \
    [file join $source_root all2x_v6 bridge_valid_quantized_to_interp2_ce.v] \
    [file join $source_root all2x_v6 round_sat_shift_compact.v] \
    [file join $source_root national_finals interp2_stage1_single_bram_serial_ce.v] \
    [file join $source_root national_finals nf_stage1_history_ramb18_sdp.v] \
    [file join $source_root national_finals nf_stage23_history_ramb18_sdp.v] \
    [file join $source_root national_finals nf_unified_fir_coeff_bram.v] \
    [file join $source_root national_finals experiments interp2_stage23_fixed256_dsp_ce.v] \
    [file join $script_dir fixed256_stage23_front_ooc_wrapper.v]]
read_verilog $sources
synth_design -top fixed256_stage23_front_ooc_wrapper \
    -part xc7a35tfgg484-2 -mode out_of_context \
    -include_dirs $include_dirs -flatten_hierarchy $flatten_mode \
    -directive $synth_directive -resource_sharing on -shreg_min_size 5
create_clock -name fir_clk_12m288 -period 81.380 [get_ports clk]
set utilization [report_utilization -return_string]
report_utilization -file [file join $work_dir utilization_post_synth.rpt]
report_utilization -hierarchical -hierarchical_min_primitive_count 0 \
    -file [file join $work_dir utilization_hierarchical_post_synth.rpt]
report_timing_summary -file [file join $work_dir timing_post_synth.rpt]
write_checkpoint -force [file join $work_dir post_synth.dcp]
regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} $utilization unused lut_count
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} $utilization unused ff_count
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set fid [open [file join $work_dir result.txt] w]
puts $fid "STAGE=POST_SYNTH"
puts $fid "LUT=$lut_count"
puts $fid "FF=$ff_count"
puts $fid "DSP48E1=$dsp_count"
puts $fid "RAMB18E1=$bram18_count"
close $fid
puts "FIXED256_STAGE23_FRONT_LUT=$lut_count"
puts "FIXED256_STAGE23_FRONT_FF=$ff_count"
puts "FIXED256_STAGE23_FRONT_DSP=$dsp_count"
puts "FIXED256_STAGE23_FRONT_RAMB18=$bram18_count"
