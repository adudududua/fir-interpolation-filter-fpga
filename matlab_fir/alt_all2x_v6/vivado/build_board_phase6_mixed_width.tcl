#=============================================================
# 文件名       : build_board_phase6_mixed_width.tcl
# 脚本名       : build_board_phase6_mixed_width
# 功能简述     : 重置并重跑 Phase 6 混合数据字长四档板级工程的
#                综合、实现和 bitstream，导出资源、时序、功耗
#                与 DRC 报告。
#
#                本脚本直接打开现有 XC7A35T Vivado 工程，先检查
#                三个 Phase 6 板级源文件均已登记，再清除 synth_1
#                和 impl_1 的旧结果，避免误用历史网表。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  工作模式：1x / 4x / 8x / 128x
#                  数据字长：24/22/20/18/18/18/18bit
#                  Stage 2/3：共享 DSP、Q15、ACC_W=38
#                  目标器件：xc7a35tfgg484-2
#                  输出目录：alt_all2x_v6/vivado_results/
#                              board_mixed_width
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-13
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-13：新增 Phase 6 混合字长板级构建脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set v6_src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs \
    sources_1 new all2x_v6]
set required_files [list \
    [file join $v6_src_dir round_sat_shift_compact.v] \
    [file join $v6_src_dir bridge_valid_quantized_to_interp2_ce.v] \
    [file join $v6_src_dir interp128_all2x_v6_mixed_width_top_ce.v]]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results board_mixed_width]]

file mkdir $result_dir
open_project $project_file

foreach required_file $required_files {
    if {[llength [get_files -quiet $required_file]] == 0} {
        error "Phase 6 source is not registered: $required_file"
    }
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 6 board synthesis did not complete."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 6 board implementation did not complete."
}

open_run impl_1
report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.rpt]
report_utilization -file \
    [file join $result_dir utilization_placed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file \
    [file join $result_dir timing_summary_routed.rpt]
report_power -file [file join $result_dir power_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]

set bitstream_src [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "Phase 6 board bitstream was not generated."
}
file copy -force $bitstream_src \
    [file join $result_dir \
        board_demo_competition_dac8_top_phase6_mixed_width.bit]

puts "Phase 6 mixed-width board build completed."
close_project
