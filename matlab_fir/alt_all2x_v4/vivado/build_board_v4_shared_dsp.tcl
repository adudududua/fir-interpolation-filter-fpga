#=============================================================
# 文件名       : build_board_v4_shared_dsp.tcl
# 脚本名       : build_board_v4_shared_dsp
# 功能简述     : 将 V4 Stage 2/3 共享 DSP 链正式登记到板级工程，
#                更新 sources_1 编译顺序，重跑 synth_1 与 impl_1
#                至 bitstream，并导出资源、时序、DRC 和功耗报告。
#
# 当前默认配置：
#                  工程文件：XC7A35T_interp.xpr
#                  板级顶层：board_demo_competition_dac8_top
#                  综合运行：synth_1
#                  实现运行：impl_1
#                  目标器件：xc7a35tfgg484-2
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-12
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-12：新增 V4 共享 DSP 板级自动构建脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set src_dir [file join $project_dir \
    XC7A35T_interp.srcs sources_1 new]
set v2_src_dir [file join $src_dir all2x_v2]
set v3_src_dir [file join $src_dir all2x_v3]
set v4_src_dir [file join $src_dir all2x_v4]
set result_dir [file normalize [file join $script_dir .. \
    board_results]]

file mkdir $result_dir
open_project $project_file

set v4_files [list \
    [file join $v4_src_dir interp2_stage23_shared_dsp_ce.v] \
    [file join $v4_src_dir interp128_all2x_v4_shared_dsp_top_ce.v]]

foreach source_file $v4_files {
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
    }
}

set include_dirs [get_property include_dirs [get_filesets sources_1]]
foreach include_dir [list $v2_src_dir $v3_src_dir $v4_src_dir] {
    if {[lsearch -exact $include_dirs $include_dir] < 0} {
        lappend include_dirs $include_dir
    }
}
set_property include_dirs $include_dirs [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "V4 board synthesis did not complete."
}

open_run synth_1
report_utilization -hierarchical -file \
    [file join $result_dir synth_utilization_hierarchical.txt]
report_utilization -file \
    [file join $result_dir synth_utilization_summary.txt]
report_timing_summary -delay_type max -max_paths 10 -file \
    [file join $result_dir synth_timing_summary.txt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "V4 board implementation did not complete."
}

open_run impl_1
report_utilization -hierarchical -file \
    [file join $result_dir impl_utilization_hierarchical.txt]
report_utilization -file \
    [file join $result_dir impl_utilization_summary.txt]
report_timing_summary -delay_type min_max -max_paths 20 -file \
    [file join $result_dir impl_timing_summary.txt]
report_drc -file [file join $result_dir impl_drc.txt]
report_power -file [file join $result_dir impl_power.txt]

puts "Phase 4 V4 shared DSP board build completed."
close_project
