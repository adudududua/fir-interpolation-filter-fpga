#=============================================================
# 文件名       : add_all2x_v2_to_project.tcl
# 脚本名       : add_all2x_v2_to_project
# 功能简述     : 将全 2x V2 Phase 2 RTL 正式加入当前 Vivado 工程。
#                本脚本添加板级实现所需的 7 个 V2 文件，配置
#                Verilog 头文件搜索路径，更新编译顺序，并清除
#                旧综合与实现结果，防止继续读取旧资源报告。
#
#                使用方法：
#                  1. 在 Vivado 中打开 XC7A35T_interp 工程；
#                  2. 在 Tcl Console 中执行：
#                     source D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/XC7A35T_interp_audio_pcm_wordlen_opt/add_all2x_v2_to_project.tcl
#
#                当前默认配置：
#                  工程文件集：sources_1
#                  板级顶层  ：board_demo_competition_dac8_top
#                  V2 顶层   ：interp128_all2x_v2_lightbridge_top_ce
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-11
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-11：新增 V2 Phase 2 板级工程接入脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set source_dir [file join $script_dir XC7A35T_interp.srcs sources_1 new]
set v2_dir     [file join $source_dir all2x_v2]
set opened_here 0

if {[llength [get_projects -quiet]] == 0} {
    open_project [file join $script_dir XC7A35T_interp.xpr]
    set opened_here 1
}

set v2_files [list \
    [file join $v2_dir all2x_v2_coeff_pkg.vh] \
    [file join $v2_dir bridge_valid_only_to_interp2_ce.v] \
    [file join $v2_dir interp2_halfband7_shiftadd_ce.v] \
    [file join $v2_dir interp2_all2x_v2_stage_select.v] \
    [file join $v2_dir interp2_stage23_polyphase_ce.v] \
    [file join $v2_dir interp2_stage23_v2_select.v] \
    [file join $v2_dir interp128_all2x_v2_lightbridge_top_ce.v] \
]

foreach source_file $v2_files {
    if {![file exists $source_file]} {
        error "缺少 V2 源文件：$source_file"
    }
}

set files_to_add [list]
foreach source_file $v2_files {
    if {[llength [get_files -quiet $source_file]] == 0} {
        lappend files_to_add $source_file
    }
}

if {[llength $files_to_add] > 0} {
    add_files -norecurse -fileset sources_1 $files_to_add
}

set coeff_header [get_files -quiet [file join $v2_dir all2x_v2_coeff_pkg.vh]]
set_property FILE_TYPE "Verilog Header" $coeff_header
set_property IS_GLOBAL_INCLUDE true $coeff_header

set include_dirs [get_property INCLUDE_DIRS [get_filesets sources_1]]
if {[lsearch -exact $include_dirs $v2_dir] < 0} {
    lappend include_dirs $v2_dir
    set_property INCLUDE_DIRS $include_dirs [get_filesets sources_1]
}

set dependency_names [list \
    interp2_ctrl_ce.v \
    round_sat_q16_to24.v \
    fir_core_symm_interp2_all2x.v \
    fir_core_symm_interp2_stage1_mac.v \
    interp2_top_symm_ce_all2x.v \
]

foreach dependency_name $dependency_names {
    set dependency_file [get_files -quiet */$dependency_name]
    if {[llength $dependency_file] == 0} {
        error "工程中缺少公共依赖文件：$dependency_name"
    }
    set_property USED_IN_SYNTHESIS true $dependency_file
    set_property USED_IN_IMPLEMENTATION true $dependency_file
    set_property USED_IN_SIMULATION true $dependency_file
}

set_property TOP board_demo_competition_dac8_top [get_filesets sources_1]
update_compile_order -fileset sources_1

catch {close_design}

if {[llength [get_runs -quiet impl_1]] > 0} {
    reset_run impl_1
}
if {[llength [get_runs -quiet synth_1]] > 0} {
    reset_run synth_1
}

puts "============================================================="
puts "全 2x V2 Phase 2 已加入 sources_1。"
puts "板级顶层：board_demo_competition_dac8_top"
puts "插值顶层：interp128_all2x_v2_lightbridge_top_ce"
puts "旧综合/实现结果已重置，请重新运行 Synthesis 和 Implementation。"
puts "============================================================="

if {$opened_here} {
    close_project
}
