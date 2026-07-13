#=============================================================
# 文件名       : register_phase7_board_sources.tcl
# 脚本名       : register_phase7_board_sources
# 功能简述     : 将 Phase 7 折叠补偿 FIR-CIC 的综合源文件和位真
#                测试平台登记到现有 Vivado 工程，并把 all2x_v7
#                加入 Verilog include 路径。脚本可重复执行，不会
#                重复添加已有文件，也不会启动综合或实现。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  板级候选：N=3，CIC 全精度
#                  回退路径：Phase 6 源文件继续保留在工程中
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-13
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-13：新增 Phase 7 板级源文件登记脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set project_src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs]
set v7_src_dir [file join $project_src_dir sources_1 new all2x_v7]
set v7_sim_dir [file join $project_src_dir sim_1 new all2x_v7]

set source_files [list \
    [file join $v7_src_dir interp2_stage23_folded_cic_dsp_ce.v] \
    [file join $v7_src_dir cic_interp16_core_ce.v] \
    [file join $v7_src_dir interp128_all2x_v7_folded_fir_cic_top_ce.v]]
set simulation_files [list \
    [file join $v7_sim_dir tb_cic_interp16_folded_core.v] \
    [file join $v7_sim_dir tb_phase7_folded_front3_bittrue.v]]

open_project $project_file

foreach source_file $source_files {
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
    }
}
foreach simulation_file $simulation_files {
    if {[llength [get_files -quiet $simulation_file]] == 0} {
        add_files -fileset sim_1 -norecurse $simulation_file
    }
}

set include_dirs [get_property include_dirs [get_filesets sources_1]]
if {[lsearch -exact $include_dirs $v7_src_dir] < 0} {
    lappend include_dirs $v7_src_dir
}
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property top board_demo_competition_dac8_top [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Phase 7 board sources registered successfully."
close_project
