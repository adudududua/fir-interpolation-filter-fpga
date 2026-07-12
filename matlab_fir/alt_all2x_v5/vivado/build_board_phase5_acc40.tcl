#=============================================================
# 文件名       : build_board_phase5_acc40.tcl
# 脚本名       : build_board_phase5_acc40
# 功能简述     : 重置并重跑 Phase 5 ACC40 四档板级工程的综合、
#                实现和 bitstream，导出资源、时序和 DRC 报告。
#
#                本脚本直接打开现有 XC7A35T Vivado 工程，先检查
#                紧凑 Q15 舍入源文件已登记，再清除 synth_1 和
#                impl_1 的旧结果，避免误用历史网表。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  工作模式：1x / 4x / 8x / 128x
#                  Stage 2/3：Q15 紧凑舍入、ACC_W=40
#                  目标器件：xc7a35tfgg484-2
#                  输出目录：alt_all2x_v5/vivado_results/board_acc40
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-12
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-12：新增 Phase 5 ACC40 板级构建脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set compact_round_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs \
    sources_1 new all2x_v5 round_sat_q15_compact_to24.v]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results board_acc40]]

file mkdir $result_dir
open_project $project_file

if {[llength [get_files -quiet $compact_round_file]] == 0} {
    error "Phase 5 compact rounder is not registered in the project."
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 5 board synthesis did not complete."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 5 board implementation did not complete."
}

open_run impl_1
report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.rpt]
report_utilization -file \
    [file join $result_dir utilization_placed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file \
    [file join $result_dir timing_summary_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]

set bitstream_src [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "Phase 5 board bitstream was not generated."
}
file copy -force $bitstream_src \
    [file join $result_dir board_demo_competition_dac8_top_phase5_acc40.bit]

puts "Phase 5 ACC40 board synthesis, implementation and bitstream completed."
close_project
