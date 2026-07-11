#=============================================================
# 文件名       : synth_stage1_strict_bram.tcl
# 脚本名       : synth_stage1_strict_bram
# 功能简述     : 对 V3 Phase 3C Stage 1 strict-halfband BRAM 版本
#                执行独立综合，导出层次资源、总资源、时序和检查点。
#
# 当前默认配置：
#                  FPGA 型号：xc7a35tfgg484-2
#                  顶层模块：interp128_all2x_v3_strict_s1_bram_top_ce
#                  Stage 1 ：105 tap Q15，64x24bit BRAM 循环缓冲
#                  Stage 2/3：V2 true-polyphase
#                  Stage 4～7：canonical Q4 shift-add
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-11
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-11：新增 Stage 1 strict-halfband BRAM 综合脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set v2_src_dir [file join $src_dir all2x_v2]
set v3_src_dir [file join $src_dir all2x_v3]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results phase3_stage1_strict_bram]]

file mkdir $result_dir

read_verilog [list \
    [file join $src_dir interp2_ctrl_ce.v] \
    [file join $src_dir bridge_to_interp2_ce.v] \
    [file join $src_dir round_sat_q16_to24.v] \
    [file join $src_dir fir_core_symm_interp2_all2x.v] \
    [file join $src_dir fir_core_symm_interp2_stage1_mac.v] \
    [file join $src_dir interp2_top_symm_ce_all2x.v] \
    [file join $v2_src_dir bridge_valid_only_to_interp2_ce.v] \
    [file join $v2_src_dir interp2_halfband7_shiftadd_ce.v] \
    [file join $v2_src_dir interp2_all2x_v2_stage_select.v] \
    [file join $v2_src_dir interp2_stage23_polyphase_ce.v] \
    [file join $v2_src_dir interp2_stage23_v2_select.v] \
    [file join $v3_src_dir interp2_stage1_strict_halfband_mac_ce.v] \
    [file join $v3_src_dir interp2_stage1_strict_halfband_bram_ce.v] \
    [file join $v3_src_dir interp128_all2x_v3_stage1_select_top_ce.v] \
    [file join $v3_src_dir interp128_all2x_v3_strict_s1_bram_top_ce.v]]

set_property include_dirs [list $v2_src_dir $v3_src_dir] [current_fileset]

synth_design -top interp128_all2x_v3_strict_s1_bram_top_ce \
    -part xc7a35tfgg484-2

create_clock -name clk_audio_5m6448 -period 177.154 [get_ports clk]

report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.txt]
report_utilization -file \
    [file join $result_dir utilization_summary.txt]
report_timing_summary -delay_type max -max_paths 10 -file \
    [file join $result_dir timing_summary.txt]
write_checkpoint -force [file join $result_dir post_synth.dcp]

puts "Phase 3 Stage 1 strict-halfband BRAM synthesis completed."
