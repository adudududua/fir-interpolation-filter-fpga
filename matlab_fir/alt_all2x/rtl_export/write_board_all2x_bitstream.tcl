#=============================================================
# 文件名       : write_board_all2x_bitstream.tcl
# 脚本名       : write_board_all2x_bitstream
# 功能简述     : 基于已完成布局布线的全 2x 板级工程生成 bitstream，
#                并复制到 reports_all2x_board 正式报告目录。
#
#                输出文件：
#                  board_demo_competition_dac8_top_all2x.bit
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-10
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-10：新增全 2x 板级 bitstream 生成脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt]
set project_path [file join $project_dir XC7A35T_interp.xpr]
set report_dir [file join $project_dir reports_all2x_board]

file mkdir $report_dir
open_project $project_path

set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*route_design Complete*" $impl_status] &&
    ![string match "*write_bitstream Complete*" $impl_status]} {
    error "impl_1 is not routed: $impl_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

set bit_status [get_property STATUS [get_runs impl_1]]
if {![string match "*write_bitstream Complete*" $bit_status] ||
    [string match "*Failed*" $bit_status]} {
    error "write_bitstream failed: $bit_status"
}

set run_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_src [file join $run_dir board_demo_competition_dac8_top.bit]
set bit_dst [file join $report_dir board_demo_competition_dac8_top_all2x.bit]

file copy -force $bit_src $bit_dst
puts "Board all-2x bitstream completed: $bit_dst"

close_project
