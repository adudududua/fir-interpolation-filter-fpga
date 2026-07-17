#=============================================================
# 文件名       : build_board_phase7_folded_n3_bram_rom.tcl
# 脚本名       : build_board_phase7_folded_n3_bram_rom
# 功能简述     : 构建 Phase 7 N=3 折叠补偿 FIR-CIC 的保守资源
#                优化板级版本。保持 FIR-CIC 数据通路、四档 DAC
#                接口和 0.50FS 演示正弦不变，仅使 147x24bit
#                PCM ROM 稳定推断为一个 RAMB18E1。
#
#                本脚本重跑综合、实现和 bitstream，并将资源、
#                时序、DSP、BRAM、功耗和 DRC 报告写入独立目录，
#                不覆盖已完成板测的 Phase 7 稳定版结果。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  演示信号：15kHz / 0.50FS / 44.1kHz PCM
#                  工作模式：1x / 4x / 8x / 128x
#                  插值结构：2x x 2x x 2x x CIC16
#                  目标器件：xc7a35tfgg484-2
#                  输出目录：alt_all2x_v7/vivado_results/
#                            board_folded_n3_bram_rom
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-17
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-17：新增 PCM ROM Block RAM 优化构建。
#                2026-07-17：输入幅度改为已板测正常的 0.50FS。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set common_src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs \
    sources_1 new]
set v7_src_dir [file join $common_src_dir all2x_v7]
set required_files [list \
    [file join $common_src_dir audio_pcm_rom_source.v] \
    [file join $common_src_dir demo_sine_15k_44k1_24bit_147.mem] \
    [file join $v7_src_dir interp2_stage23_folded_cic_dsp_ce.v] \
    [file join $v7_src_dir cic_interp16_core_ce.v] \
    [file join $v7_src_dir interp128_all2x_v7_folded_fir_cic_top_ce.v]]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results board_folded_n3_bram_rom]]

proc write_primitive_report {report_file pattern title} {
    set primitive_cells [get_cells -hierarchical \
        -filter [format {REF_NAME =~ %s} $pattern]]
    set report_handle [open $report_file w]
    puts $report_handle $title
    puts $report_handle [string repeat "=" [string length $title]]
    puts $report_handle "Cell count: [llength $primitive_cells]"
    foreach primitive_cell $primitive_cells {
        puts $report_handle [format "%s | %s | %s" $primitive_cell \
            [get_property REF_NAME $primitive_cell] \
            [get_property LOC $primitive_cell]]
    }
    close $report_handle
}

file mkdir $result_dir
open_project $project_file

foreach required_file $required_files {
    if {[llength [get_files -quiet $required_file]] == 0} {
        error "Phase 7 BRAM ROM source is not registered: $required_file"
    }
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 7 BRAM ROM synthesis did not complete."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 7 BRAM ROM implementation did not complete."
}

open_run impl_1
report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.rpt]
report_utilization -file \
    [file join $result_dir utilization_placed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file \
    [file join $result_dir timing_summary_routed.rpt]
report_clock_interaction -delay_type min_max -file \
    [file join $result_dir clock_interaction_routed.rpt]
write_primitive_report [file join $result_dir dsp_utilization_routed.rpt] \
    "DSP48*" "Phase 7 implemented DSP utilization"
write_primitive_report [file join $result_dir bram_utilization_routed.rpt] \
    "RAMB18*" "Phase 7 implemented RAMB18 utilization"
report_power -file [file join $result_dir power_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]

set bitstream_src [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.runs impl_1 \
    board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "Phase 7 BRAM ROM bitstream was not generated."
}
file copy -force $bitstream_src \
    [file join $result_dir \
        board_demo_competition_dac8_top_phase7_folded_n3_bram_rom_amp050.bit]

puts "Phase 7 folded N=3 BRAM ROM board build completed."
close_project
