#=============================================================
# 文件名       : synth_lightbridge.tcl
# 脚本名       : synth_lightbridge
# 功能简述     : 综合 Phase 2 最优 S2～S3 true-polyphase 加
#                valid-only 轻量桥接候选，导出资源和时序报告。
#
# 当前默认配置：
#                  FPGA 型号：xc7a35tfgg484-2
#                  顶层模块：interp128_all2x_v2_lightbridge_top_ce
#                  DSP 数量 ：1
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-11
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-11：新增 Phase 2 轻量桥接综合脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set v2_src_dir [file join $src_dir all2x_v2]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results phase2_lightbridge]]

file mkdir $result_dir

read_verilog [list \
    [file join $src_dir interp2_ctrl_ce.v] \
    [file join $src_dir round_sat_q16_to24.v] \
    [file join $src_dir fir_core_symm_interp2_all2x.v] \
    [file join $src_dir fir_core_symm_interp2_stage1_mac.v] \
    [file join $src_dir interp2_top_symm_ce_all2x.v] \
    [file join $v2_src_dir bridge_valid_only_to_interp2_ce.v] \
    [file join $v2_src_dir interp2_halfband7_shiftadd_ce.v] \
    [file join $v2_src_dir interp2_all2x_v2_stage_select.v] \
    [file join $v2_src_dir interp2_stage23_polyphase_ce.v] \
    [file join $v2_src_dir interp2_stage23_v2_select.v] \
    [file join $v2_src_dir interp128_all2x_v2_lightbridge_top_ce.v]]

set_property include_dirs [list $v2_src_dir] [current_fileset]

synth_design -top interp128_all2x_v2_lightbridge_top_ce \
    -part xc7a35tfgg484-2 \
    -generic FIRST_CANONICAL_STAGE=4 \
    -generic FIRST_TRUE_POLYPHASE_STAGE=2

create_clock -name clk_audio_5m6448 -period 177.154 [get_ports clk]

report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.txt]
report_utilization -file \
    [file join $result_dir utilization_summary.txt]
report_timing_summary -delay_type max -max_paths 10 -file \
    [file join $result_dir timing_summary.txt]
write_checkpoint -force [file join $result_dir post_synth.dcp]

puts "Phase 2 lightbridge synthesis completed."
