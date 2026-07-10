#=============================================================
# 文件名       : synth_all2x_stage1_mac.tcl
# 脚本名       : synth_all2x_stage1_mac
# 功能简述     : 对 Stage 1 单乘法器时分复用的全 2x RTL 进行独立
#                综合，导出资源利用率和时序报告。
#
#                输出文件：
#                  all2x_stage1_mac_lut_tail_utilization.txt
#                  all2x_stage1_mac_lut_tail_timing.txt
#
# 当前默认配置：
#                  FPGA 型号：xc7a35tfgg484-2
#                  顶层模块：interp128_all2x_top_ce
#                  时钟频率：5.6448MHz
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-10
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-10：新增 Stage 1 单 MAC 资源综合脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]

read_verilog [list \
    [file join $src_dir interp2_ctrl_ce.v] \
    [file join $src_dir bridge_to_interp2_ce.v] \
    [file join $src_dir round_sat_q16_to24.v] \
    [file join $src_dir fir_core_symm_interp2_all2x.v] \
    [file join $src_dir fir_core_symm_interp2_stage1_mac.v] \
    [file join $src_dir interp2_top_symm_ce_all2x.v] \
    [file join $src_dir interp128_all2x_top_ce.v]]

synth_design -top interp128_all2x_top_ce -part xc7a35tfgg484-2

create_clock -name clk_audio_5m6448 -period 177.154 \
    [get_ports clk]

report_utilization -hierarchical -file \
    [file join $script_dir all2x_stage1_mac_lut_tail_utilization.txt]

report_timing_summary -delay_type max -max_paths 10 -file \
    [file join $script_dir all2x_stage1_mac_lut_tail_timing.txt]

puts "All-2x Stage 1 single-MAC synthesis completed."
