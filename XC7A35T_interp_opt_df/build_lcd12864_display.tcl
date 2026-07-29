#=============================================================
# 文件名       : build_lcd12864_display.tcl
# 脚本名       : build_lcd12864_display
# 功能简述     : 构建 Phase 7 低 LUT 插值链、可调正弦 NCO 与
#                12864T 图形液晶界面。
#                保持 FIR/CIC、矩阵键盘、四档 DAC 和面积优先策略
#                不变，重跑综合、实现、bitstream，并导出液晶版本
#                的资源、时序、DRC 和时钟交互报告。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  工作模式：1x / 4x / 8x / 128x
#                  液晶接口：12864T / ST7920 兼容 8bit 并口
#                  输入信号：1kHz～20kHz / 0.50FS 可调正弦 NCO
#                  液晶页面：倍率、输出率、输入频率、SW1～SW8
#                  目标器件：xc7a35tfgg484-2
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-18
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-18：新增 12864T 显示版完整构建脚本。
#                2026-07-18：加入可调NCO、频率按键和动态显示构建。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir XC7A35T_interp.xpr]
set report_dir [file join $script_dir reports_lcd12864]

file mkdir $report_dir
open_project $project_file

# Keep the proven low-LUT implementation directives used by the Phase 7
# board build while adding the display subsystem.
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea [get_runs impl_1]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 did not complete"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "impl_1 did not complete"
}

open_run impl_1
report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]

set bit_source [file join $script_dir XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
set bit_target [file join $report_dir \
    board_demo_competition_dac8_top_lcd12864.bit]
file copy -force $bit_source $bit_target

set sha_file [open [file join $report_dir build_summary.txt] w]
puts $sha_file "bitstream=$bit_target"
puts $sha_file "part=[get_property PART [current_design]]"
puts $sha_file "synth_directive=[get_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE [get_runs synth_1]]"
puts $sha_file "opt_directive=[get_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]]"
close $sha_file

close_project
exit
