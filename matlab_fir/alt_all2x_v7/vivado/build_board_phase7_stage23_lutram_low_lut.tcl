#=============================================================
# 文件名       : build_board_phase7_stage23_lutram_low_lut.tcl
# 脚本名       : build_board_phase7_stage23_lutram_low_lut
# 功能简述     : 构建 Phase 7 Stage 2/3 单读 LUTRAM 低 LUT 候选。
#                保持 0.50FS 正弦、FIR 系数、定点字长、CIC DSP
#                映射和四档 DAC 接口不变，仅把 Stage 2/3 历史
#                存储改为单读 LUTRAM，并利用系统时钟余量串行 MAC。
#
#                脚本完成综合、实现、bitstream，并导出层级资源、
#                原语、时序、时钟交互、功耗、DRC 与方法学报告。
#                所有结果写入独立目录，不覆盖稳定 bitstream/MCS。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  工作模式：1x / 4x / 8x / 128x
#                  插值结构：2x x 2x x 2x x CIC16
#                  Stage 2/3：单读 LUTRAM + 1 个共享 DSP48E1
#                  目标器件：xc7a35tfgg484-2
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-18
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-18：新增 Stage 2/3 LUTRAM 板级构建脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set common_src_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs sources_1 new]
set v7_src_dir [file join $common_src_dir all2x_v7]
set stage23_lutram_src [file join $v7_src_dir interp2_stage23_lutram_cic_dsp_ce.v]
set result_dir [file normalize [file join $script_dir .. vivado_results board_folded_n3_stage23_lutram_low_lut]]

proc write_primitive_report {report_file pattern title} {
    set primitive_cells [get_cells -hierarchical -filter [format {REF_NAME =~ %s} $pattern]]
    set report_handle [open $report_file w]
    puts $report_handle $title
    puts $report_handle [string repeat "=" [string length $title]]
    puts $report_handle "Cell count: [llength $primitive_cells]"
    foreach primitive_cell $primitive_cells {
        puts $report_handle [format "%s | %s | %s" \
            $primitive_cell [get_property REF_NAME $primitive_cell] \
            [get_property LOC $primitive_cell]]
    }
    close $report_handle
}

file mkdir $result_dir
open_project $project_file

if {[llength [get_files -quiet $stage23_lutram_src]] == 0} {
    add_files -fileset sources_1 -norecurse $stage23_lutram_src
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
set_property generic {USE_PHASE7_LUTRAM_STAGE23=1} [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 7 Stage 2/3 LUTRAM synthesis did not complete."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 7 Stage 2/3 LUTRAM implementation did not complete."
}

open_run impl_1
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical.rpt]
report_utilization \
    -file [file join $result_dir utilization_placed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $result_dir clock_interaction_routed.rpt]
write_primitive_report [file join $result_dir dsp_utilization_routed.rpt] \
    "DSP48*" "Phase 7 Stage 2/3 LUTRAM DSP utilization"
write_primitive_report [file join $result_dir bram_utilization_routed.rpt] \
    "RAMB*" "Phase 7 Stage 2/3 LUTRAM BRAM utilization"
write_primitive_report [file join $result_dir lutram_utilization_routed.rpt] \
    "RAMD*" "Phase 7 Stage 2/3 distributed RAM utilization"
report_power -file [file join $result_dir power_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
catch {
    report_methodology -file [file join $result_dir methodology_routed.rpt]
}
catch {
    report_cdc -details -file [file join $result_dir cdc_routed.rpt]
}
write_checkpoint -force [file join $result_dir board_phase7_stage23_lutram_routed.dcp]

set bitstream_src [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.runs impl_1 board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "Phase 7 Stage 2/3 LUTRAM bitstream was not generated."
}
file copy -force $bitstream_src \
    [file join $result_dir board_demo_competition_dac8_top_phase7_stage23_lutram_low_lut_amp050.bit]

puts "Phase 7 Stage 2/3 LUTRAM low LUT board build completed."
close_project
