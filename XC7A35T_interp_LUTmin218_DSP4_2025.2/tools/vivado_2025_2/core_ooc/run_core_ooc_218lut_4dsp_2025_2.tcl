#=============================================================
# 文件名       : run_core_ooc_218lut_4dsp_2025_2.tcl
# 功能简述     : 以正式 24/20/20 位、4-DSP 参数独立实现滤波器核心，
#                输出综合、布局布线、时序、DRC、DCP 和资源摘要。
# 版本         : V2025.2
# 开发工具     : Vivado 2025.2
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set result_dir [expr {$argc > 0 ? [file normalize [lindex $argv 0]] :
    [file join $script_dir results latest]}]
set jobs [expr {$argc > 1 ? [lindex $argv 1] : 1}]
set top_name interp128_all2x_v7_folded_fir_cic_top_ce
set part_name xc7a35tfgg484-2

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

require_condition [file isdirectory $source_root] "RTL 根目录不存在：$source_root"
require_condition [expr {$jobs >= 1 && $jobs <= 4}] "Jobs 必须在 1～4 之间。"
file mkdir $result_dir

# 这些目录提供 Verilog `include 所需的系数头文件。
set include_dirs [list \
    [file join $source_root all2x_v2] \
    [file join $source_root all2x_v3] \
    [file join $source_root all2x_v4] \
    [file join $source_root all2x_v5] \
    [file join $source_root all2x_v6] \
    [file join $source_root all2x_v7]]

# 使用签核时相同的源文件清单。脚本直接读取 RTL，不打开也不修改板级 XPR。
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
    set source_file [file join $source_root $relative_source]
    require_condition [file exists $source_file] "缺少 RTL：$source_file"
    lappend sources $source_file
}
read_verilog $sources

# 正式 218-LUT/4-DSP 板级版本对应的独立核心参数，不能使用模块默认值。
set core_generics [list \
    STAGE1_ACC_W=41 \
    STAGE23_ACC_W=38 \
    STAGE2_DATA_W=20 \
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

# 6.144 MHz 是两采样率家族中的较高核心时钟，作为 OOC 内部时序检查条件。
create_clock -name core_clk_6m144 -period 162.760 \
    -waveform {0.000 81.380} [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y16 [get_ports clk]
set_false_path -from [get_ports rst_n]
set core_data_inputs [get_ports {ce2_out ce4_out ce8_out ce16_out ce32_out \
    ce64_out ce128_out x_in x_in_valid stage3_compensated_mode}]
set_input_delay -clock [get_clocks core_clk_6m144] 0.000 $core_data_inputs
set_output_delay -clock [get_clocks core_clk_6m144] 0.000 [all_outputs]

report_utilization -file [file join $result_dir utilization_post_synth.rpt]
write_checkpoint -force [file join $result_dir core_post_synth.dcp]

opt_design -directive ExploreArea
place_design -directive Explore
route_design

set utilization_report [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_post_route.rpt]
report_utilization -hierarchical -hierarchical_min_primitive_count 0 \
    -file [file join $result_dir utilization_post_route_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir timing_post_route.rpt]
report_route_status -file [file join $result_dir route_status_post_route.rpt]
report_drc -file [file join $result_dir drc_post_route.rpt]
write_checkpoint -force [file join $result_dir core_post_route.dcp]

require_condition [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
    $utilization_report unused lut_count] "无法解析 Slice LUT 数量。"
require_condition [regexp {\|\s*LUT as Memory[^|]*\|\s*([0-9]+)\s*\|} \
    $utilization_report unused lutram_count] "无法解析 LUTRAM 数量。"
require_condition [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
    $utilization_report unused ff_count] "无法解析寄存器数量。"

set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set bram36_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]]
set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]]
set internal_registers [all_registers -clock [get_clocks core_clk_6m144]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 \
    -from $internal_registers -to $internal_registers]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 \
    -from $internal_registers -to $internal_registers]
require_condition [expr {[llength $setup_path] == 1}] "没有找到内部建立时间路径。"
require_condition [expr {[llength $hold_path] == 1}] "没有找到内部保持时间路径。"
set internal_wns [get_property SLACK $setup_path]
set internal_whs [get_property SLACK $hold_path]
report_timing -delay_type max -max_paths 20 -nworst 1 \
    -from $internal_registers -to $internal_registers \
    -file [file join $result_dir timing_internal_setup.rpt]
report_timing -delay_type min -max_paths 20 -nworst 1 \
    -from $internal_registers -to $internal_registers \
    -file [file join $result_dir timing_internal_hold.rpt]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

set summary_fid [open [file join $result_dir core_ooc_summary.txt] w]
puts $summary_fid "TOOL=Vivado 2025.2"
puts $summary_fid "VARIANT=218lut_4dsp_wordlength_24_20_20"
puts $summary_fid "TOP=$top_name"
puts $summary_fid "PART=$part_name"
puts $summary_fid "CLOCK_MHZ=6.144"
puts $summary_fid "POST_ROUTE_LUT=$lut_count"
puts $summary_fid "POST_ROUTE_LUTRAM=$lutram_count"
puts $summary_fid "POST_ROUTE_FF=$ff_count"
puts $summary_fid "POST_ROUTE_DSP48E1=$dsp_count"
puts $summary_fid "POST_ROUTE_RAMB18E1=$bram18_count"
puts $summary_fid "POST_ROUTE_RAMB36E1=$bram36_count"
puts $summary_fid "POST_ROUTE_BRAM_TILE=[expr {$bram36_count + 0.5*$bram18_count}]"
puts $summary_fid "POST_ROUTE_MMCM=$mmcm_count"
puts $summary_fid "INTERNAL_WNS_NS=$internal_wns"
puts $summary_fid "INTERNAL_WHS_NS=$internal_whs"
puts $summary_fid "POST_ROUTE_DRC_ERRORS=[llength $drc_errors]"
close $summary_fid

# 门禁保证生成的不是默认 8-DSP 版本，也不是其他历史候选参数。
require_condition [expr {$lut_count == 190}] "预期 190 LUT，实际 $lut_count。"
require_condition [expr {$lutram_count == 0}] "预期 0 LUTRAM，实际 $lutram_count。"
require_condition [expr {$ff_count == 279}] "预期 279 FF，实际 $ff_count。"
require_condition [expr {$dsp_count == 4}] "预期 4 DSP48E1，实际 $dsp_count。"
require_condition [expr {$bram18_count == 3 && $bram36_count == 0}] \
    "预期 3 RAMB18E1、0 RAMB36E1。"
require_condition [expr {$mmcm_count == 0}] "独立核心不应包含 MMCM。"
require_condition [expr {$internal_wns >= 0.0}] "内部建立时间失败：$internal_wns ns。"
require_condition [expr {$internal_whs >= 0.0}] "内部保持时间失败：$internal_whs ns。"
require_condition [expr {[llength $drc_errors] == 0}] \
    "OOC DRC 存在 [llength $drc_errors] 个错误。"

puts "CORE_OOC_LUT=$lut_count"
puts "CORE_OOC_FF=$ff_count"
puts "CORE_OOC_DSP=$dsp_count"
puts "CORE_OOC_RAMB18=$bram18_count"
puts "CORE_OOC_INTERNAL_WNS=$internal_wns"
puts "CORE_OOC_INTERNAL_WHS=$internal_whs"
puts "CORE_OOC_218LUT_4DSP_2025_2_PASS"
close_design
exit

