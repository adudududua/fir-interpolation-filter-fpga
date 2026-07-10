#=============================================================
# 文件名       : synth_board_all2x_project.tcl
# 脚本名       : synth_board_all2x_project
# 功能简述     : 打开现有 Vivado 工程，重新综合并实现 44.1kHz
#                专用全 2x 板级顶层，导出资源、时序与功耗报告。
#
#                当前默认配置：
#                  FPGA 器件：xc7a35tfgg484-2
#                  板级顶层：board_demo_competition_dac8_top
#                  输入时钟：20MHz
#                  音频时钟：5.6448MHz
#
#                输出目录：
#                  XC7A35T_interp_audio_pcm_wordlen_opt/
#                  reports_all2x_board/
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-10
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-10：新增全 2x 板级工程综合脚本。
#                2026-07-10：增加 route_design 与布局布线后报告。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt]
set project_path [file join $project_dir XC7A35T_interp.xpr]
set report_dir [file join $project_dir reports_all2x_board]

file mkdir $report_dir

open_project $project_path
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status] ||
    [string match "*Failed*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

open_run synth_1

report_utilization -hierarchical -file \
    [file join $report_dir utilization_board_all2x.txt]
report_timing_summary -delay_type max -max_paths 10 -file \
    [file join $report_dir timing_board_all2x.txt]

close_design

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status] ||
    [string match "*Failed*" $impl_status]} {
    error "impl_1 failed: $impl_status"
}

open_run impl_1

report_utilization -hierarchical -file \
    [file join $report_dir utilization_board_all2x_post_route.txt]
report_timing_summary -delay_type min_max -max_paths 10 -file \
    [file join $report_dir timing_board_all2x_post_route.txt]
report_power -file \
    [file join $report_dir power_board_all2x_post_route.txt]

puts "Board all-2x synthesis completed: $synth_status"
puts "Board all-2x implementation completed: $impl_status"
close_project
