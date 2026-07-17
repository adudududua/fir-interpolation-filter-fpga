#=============================================================
# 文件名       : build_board_phase7_rounder_compact_opt.tcl
# 脚本名       : build_board_phase7_rounder_compact_opt
# 功能简述     : 构建 Phase 7 N=3 FIR-CIC 的紧凑舍入候选版本。
#                本版本保持 0.50FS 正弦、滤波系数、逐级字长、CIC
#                结构和四档 DAC 接口不变，仅将 Stage 1 的 42bit
#                偏置舍入器改为截位加单比特进位的紧凑等价结构。
#
#                脚本在独立目录导出资源、时序、功耗、DRC 和 bitstream，
#                不覆盖已经完成板测的基线结果，便于实施后 A/B 对比。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  演示信号：15kHz / 0.50FS / 44.1kHz PCM
#                  工作模式：1x / 4x / 8x / 128x
#                  插值结构：2x x 2x x 2x x CIC16
#                  目标器件：xc7a35tfgg484-2
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-17
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-17：新增 Stage 1 紧凑舍入板级 A/B 构建。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set common_src_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs sources_1 new]
set v3_src_dir [file join $common_src_dir all2x_v3]
set v6_src_dir [file join $common_src_dir all2x_v6]
set v7_src_dir [file join $common_src_dir all2x_v7]
set required_files [list [file join $common_src_dir audio_pcm_rom_source.v] [file join $common_src_dir demo_sine_15k_44k1_24bit_147.mem] [file join $v3_src_dir interp2_stage1_strict_halfband_bram_ce.v] [file join $v6_src_dir round_sat_shift_compact.v] [file join $v7_src_dir interp2_stage23_folded_cic_dsp_ce.v] [file join $v7_src_dir cic_interp16_core_ce.v] [file join $v7_src_dir interp128_all2x_v7_folded_fir_cic_top_ce.v]]
set result_dir [file normalize [file join $script_dir .. vivado_results board_folded_n3_bram_rom_rounder_opt]]

proc write_primitive_report {report_file pattern title} {
    set primitive_cells [get_cells -hierarchical -filter [format {REF_NAME =~ %s} $pattern]]
    set report_handle [open $report_file w]
    puts $report_handle $title
    puts $report_handle [string repeat "=" [string length $title]]
    puts $report_handle "Cell count: [llength $primitive_cells]"
    foreach primitive_cell $primitive_cells {
        puts $report_handle [format "%s | %s | %s" $primitive_cell [get_property REF_NAME $primitive_cell] [get_property LOC $primitive_cell]]
    }
    close $report_handle
}

file mkdir $result_dir
open_project $project_file

foreach required_file $required_files {
    if {[llength [get_files -quiet $required_file]] == 0} {
        error "Phase 7 compact rounder source is not registered: $required_file"
    }
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 7 compact rounder synthesis did not complete."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 7 compact rounder implementation did not complete."
}

open_run impl_1
report_utilization -hierarchical -file [file join $result_dir utilization_hierarchical.rpt]
report_utilization -file [file join $result_dir utilization_placed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $result_dir timing_summary_routed.rpt]
report_clock_interaction -delay_type min_max -file [file join $result_dir clock_interaction_routed.rpt]
write_primitive_report [file join $result_dir dsp_utilization_routed.rpt] "DSP48*" "Phase 7 compact rounder DSP utilization"
write_primitive_report [file join $result_dir bram_utilization_routed.rpt] "RAMB18*" "Phase 7 compact rounder RAMB18 utilization"
report_power -file [file join $result_dir power_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]

set bitstream_src [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.runs impl_1 board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "Phase 7 compact rounder bitstream was not generated."
}
file copy -force $bitstream_src [file join $result_dir board_demo_competition_dac8_top_phase7_rounder_compact_amp050.bit]

puts "Phase 7 compact rounder board build completed."
close_project
