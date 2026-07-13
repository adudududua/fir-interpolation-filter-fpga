#=============================================================
# 文件名       : synth_phase6_baseline_48m.tcl
# 脚本名       : synth_phase6_baseline_48m
# 功能简述     : 用与 Phase 7 相同的 48MHz 约束重新综合 Phase 6
#                混合字长 FIR 基线，避免沿用旧脚本 5.6448MHz
#                CE 速率作为主时钟约束造成不公平的时序比较。
#
# 当前默认配置：
#                  FPGA 型号：xc7a35tfgg484-2
#                  顶层模块：interp128_all2x_v6_mixed_width_top_ce
#                  系统时钟：48MHz，周期 20.833ns
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-13
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-13：新增同口径 Phase 6 基线综合。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set v2_src_dir [file join $src_dir all2x_v2]
set v3_src_dir [file join $src_dir all2x_v3]
set v4_src_dir [file join $src_dir all2x_v4]
set v5_src_dir [file join $src_dir all2x_v5]
set v6_src_dir [file join $src_dir all2x_v6]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results phase6_baseline_48m]]
set temp_root [file normalize [file join $repo_dir \
    .codex_xvlog_check phase7 vivado_work]]
set temp_project_dir [file join $temp_root phase6_baseline_48m_[pid]]
file mkdir $result_dir
file mkdir $temp_root

set source_files [list \
    [file join $src_dir round_sat_q16_to24.v] \
    [file join $v5_src_dir round_sat_q15_compact_to24.v] \
    [file join $v2_src_dir bridge_valid_only_to_interp2_ce.v] \
    [file join $v2_src_dir interp2_halfband7_shiftadd_ce.v] \
    [file join $v2_src_dir interp2_all2x_v2_stage_select.v] \
    [file join $v3_src_dir interp2_stage1_strict_halfband_bram_ce.v] \
    [file join $v4_src_dir interp2_stage23_shared_dsp_ce.v] \
    [file join $v6_src_dir round_sat_shift_compact.v] \
    [file join $v6_src_dir bridge_valid_quantized_to_interp2_ce.v] \
    [file join $v6_src_dir interp128_all2x_v6_mixed_width_top_ce.v]]

set xdc_path [file join $result_dir phase6_clock_48m.xdc]
set xdc_fid [open $xdc_path w]
puts $xdc_fid {create_clock -name clk_audio_48m -period 20.833 [get_ports clk]}
close $xdc_fid

create_project phase6_baseline_48m $temp_project_dir \
    -part xc7a35tfgg484-2 -force
add_files -norecurse $source_files
add_files -fileset constrs_1 -norecurse $xdc_path
set_property include_dirs [list $v2_src_dir $v3_src_dir $v4_src_dir \
    $v5_src_dir $v6_src_dir] [get_filesets sources_1]
set_property top interp128_all2x_v6_mixed_width_top_ce \
    [get_filesets sources_1]
set_property generic [list STAGE23_ACC_W=38] [get_filesets sources_1]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 6 48MHz baseline synthesis did not complete."
}

open_run synth_1
report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.txt]
report_utilization -file \
    [file join $result_dir utilization_summary.txt]
report_timing_summary -delay_type min_max -max_paths 20 -file \
    [file join $result_dir timing_summary.txt]
report_power -file [file join $result_dir power_summary.txt]
set dsp_fid [open [file join $result_dir dsp_utilization.txt] w]
set dsp_cells [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
puts $dsp_fid "DSP48E1 count = [llength $dsp_cells]"
foreach dsp_cell $dsp_cells {
    puts $dsp_fid "CELL = $dsp_cell"
}
close $dsp_fid
write_checkpoint -force [file join $result_dir post_synth.dcp]
puts "Phase 6 48MHz baseline synthesis completed."
close_project
