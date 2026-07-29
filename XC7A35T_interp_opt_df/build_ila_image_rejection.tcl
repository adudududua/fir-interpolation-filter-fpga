#=============================================================
# 文件名       : build_ila_image_rejection.tcl
# 脚本名       : build_ila_image_rejection
# 功能简述     : 构建保留原液晶/DAC/按键功能的 ILA 镜像抑制版本，
#                输出 bit、ltx、资源、时序、DRC 与时钟交互报告。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-19：新增 ILA 演示完整构建脚本。
#                2026-07-19：强制重建双输出Clock Wizard，并导出
#                            100MHz Debug Hub修正版BIT/LTX。
#                2026-07-19：输出增加DAC码流和逐级采样率的23探针版本。
#                2026-07-19：输出增加独立100MHz DAC_CLK测频的
#                            26探针版本。
#                2026-07-19：修正impl_only在刷新ILA输出产品后未重建
#                            OOC检查点而产生黑盒的问题。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir XC7A35T_interp.xpr]
set report_dir [file join $script_dir reports_ila_dac_rate_freqmeter100m]
set implementation_only [expr {$argc > 0 &&
    [string equal [lindex $argv 0] "impl_only"]}]

file mkdir $report_dir
open_project $project_file
source [file join $script_dir configure_ila_image_rejection_project.tcl]

set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea [get_runs impl_1]

if {!$implementation_only} {
    set audio_clock_run [get_runs clk_wiz_audio_44k1_synth_1]
    reset_run $audio_clock_run
    launch_runs $audio_clock_run -jobs 4
    wait_on_run $audio_clock_run
    if {[get_property PROGRESS $audio_clock_run] ne "100%"} {
        error "clk_wiz_audio_44k1_synth_1 did not complete"
    }

    set ila_run [get_runs ila_image_rejection_synth_1]
    reset_run $ila_run
    launch_runs $ila_run -jobs 4
    wait_on_run $ila_run
    if {[get_property PROGRESS $ila_run] ne "100%"} {
        error "ila_image_rejection_synth_1 did not complete"
    }

    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "synth_1 did not complete"
    }
} else {
    # configure脚本会清除并重新生成ILA输出产品。Vivado 2018.3随后会
    # 删除旧OOC检查点，因此即使顶层综合仍有效，也必须先重建ILA DCP。
    set ila_run [get_runs ila_image_rejection_synth_1]
    reset_run $ila_run
    launch_runs $ila_run -jobs 4
    wait_on_run $ila_run
    if {[get_property PROGRESS $ila_run] ne "100%"} {
        error "ila_image_rejection_synth_1 did not complete"
    }

    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "impl_only requested but synth_1 is not complete"
    }
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "impl_1 did not complete"
}

open_run impl_1
report_utilization -hierarchical \
    -file [file join $report_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_clock_interaction \
    -file [file join $report_dir clock_interaction.rpt]

set bit_source [file join $script_dir XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
set bit_target [file join $report_dir \
    board_demo_competition_dac8_top_ila_dac_rate_freqmeter100m.bit]
set ltx_target [file join $report_dir \
    board_demo_competition_dac8_top_ila_dac_rate_freqmeter100m.ltx]

file copy -force $bit_source $bit_target
write_debug_probes -force $ltx_target

set summary_file [open [file join $report_dir build_summary.txt] w]
puts $summary_file "bitstream=reports_ila_dac_rate_freqmeter100m/[file tail $bit_target]"
puts $summary_file "debug_probes=reports_ila_dac_rate_freqmeter100m/[file tail $ltx_target]"
puts $summary_file "part=[get_property PART [current_design]]"
puts $summary_file "ila_depth=4096"
puts $summary_file "ila_probes=26"
puts $summary_file "demo_key=SW9"
puts $summary_file "debug_hub_clock_net=clk_debug_100m"
puts $summary_file "debug_hub_clock_hz=100000000"
puts $summary_file "dac_frequency_reference_hz=100000000"
puts $summary_file "dac_frequency_window_ms=100"
puts $summary_file "dac_frequency_resolution_hz=10"
close $summary_file

close_project
exit
