#=============================================================
# 文件名       : add_all2x_v3_to_project.tcl
# 脚本名       : add_all2x_v3_to_project
# 功能简述     : 将全 2x V3 Stage 1 严格半带优化 RTL 注册到
#                XC7A35T_interp Vivado 工程的 sources_1 中。
#
#                脚本会完成：
#                  1. 添加 V3 Verilog 源文件和系数头文件；
#                  2. 设置系数头文件为全局 Verilog Include；
#                  3. 添加 all2x_v3 头文件搜索目录；
#                  4. 保持板级顶层为 board_demo_competition_dac8_top；
#                  5. 更新编译顺序并重置旧综合、实现结果。
#
#                可在已打开工程的 Vivado Tcl Console 中执行：
#                  source D:/FpgaProject/XilinxProject/XC7A35T/
#                         fir_interpolation/XC7A35T_interp_audio_pcm_wordlen_opt/
#                         add_all2x_v3_to_project.tcl
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-12
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-12：新增 V3 板级工程注册脚本。
#=============================================================

set script_dir [file normalize [file dirname [info script]]]
set project_file [file join $script_dir "XC7A35T_interp.xpr"]
set v3_dir [file join $script_dir \
    "XC7A35T_interp.srcs" "sources_1" "new" "all2x_v3"]

set opened_here 0
if {[llength [get_projects -quiet]] == 0} {
    open_project $project_file
    set opened_here 1
}

set v3_files [list \
    [file join $v3_dir "all2x_v3_stage1_coeff_pkg.vh"] \
    [file join $v3_dir "interp2_stage1_strict_halfband_mac_ce.v"] \
    [file join $v3_dir "interp2_stage1_strict_halfband_bram_ce.v"] \
    [file join $v3_dir "interp128_all2x_v3_stage1_select_top_ce.v"] \
    [file join $v3_dir "interp128_all2x_v3_strict_s1_top_ce.v"] \
    [file join $v3_dir "interp128_all2x_v3_strict_s1_bram_top_ce.v"]]

foreach source_file $v3_files {
    if {![file exists $source_file]} {
        error "V3 source file not found: $source_file"
    }
}

set files_to_add [list]
foreach source_file $v3_files {
    if {[llength [get_files -quiet $source_file]] == 0} {
        lappend files_to_add $source_file
    }
}

if {[llength $files_to_add] > 0} {
    add_files -norecurse -fileset sources_1 $files_to_add
}

set coeff_header [get_files -quiet \
    [file join $v3_dir "all2x_v3_stage1_coeff_pkg.vh"]]
set_property FILE_TYPE "Verilog Header" $coeff_header
set_property IS_GLOBAL_INCLUDE true $coeff_header

set include_dirs [get_property INCLUDE_DIRS [get_filesets sources_1]]
if {[lsearch -exact $include_dirs $v3_dir] < 0} {
    lappend include_dirs $v3_dir
    set_property INCLUDE_DIRS $include_dirs [get_filesets sources_1]
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
puts "全 2x V3 板级工程注册完成。"
puts "板级插值入口：interp128_all2x_v3_strict_s1_bram_top_ce"
puts "下一步：重新运行 Synthesis 和 Implementation。"
puts "============================================================="

if {$opened_here} {
    close_project
}
