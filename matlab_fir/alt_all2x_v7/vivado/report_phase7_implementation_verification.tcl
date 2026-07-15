#=============================================================
# 文件名       : report_phase7_implementation_verification.tcl
# 脚本名       : report_phase7_implementation_verification
# 功能简述     : 打开已经完成的 Phase 7 板级实现结果，补充导出
#                时钟交互和 DSP 利用率报告。该脚本只读取当前
#                impl_1，不重置综合、不重新布局布线，也不修改
#                bitstream。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  实现运行：impl_1
#                  输出目录：alt_all2x_v7/vivado_results/
#                              board_folded_n3
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-14
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-14：新增 Phase 7 实现补充报告脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results board_folded_n3]]

proc write_phase7_dsp_report {report_file} {
    set dsp_cells [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]
    set report_handle [open $report_file w]
    puts $report_handle "Phase 7 implemented DSP utilization"
    puts $report_handle "=================================="
    puts $report_handle "DSP48 cell count: [llength $dsp_cells]"
    foreach dsp_cell $dsp_cells {
        puts $report_handle [format "%s | %s | %s" $dsp_cell \
            [get_property REF_NAME $dsp_cell] \
            [get_property LOC $dsp_cell]]
    }
    close $report_handle
}

file mkdir $result_dir
open_project $project_file

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 7 impl_1 is not complete. Run the board build first."
}

open_run impl_1
report_clock_interaction -delay_type min_max -file \
    [file join $result_dir clock_interaction_routed.rpt]
write_phase7_dsp_report \
    [file join $result_dir dsp_utilization_routed.rpt]

puts "Phase 7 clock interaction and DSP reports completed."
close_project
