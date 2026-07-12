#=============================================================
# 文件名       : synth_phase5_q15_single_rounder.tcl
# 脚本名       : synth_phase5_q15_single_rounder
# 功能简述     : 对 Phase 5 Q15 单舍入器完整七级插值链执行
#                独立综合，导出总资源、层次资源、DSP 映射、
#                时序和检查点，并与 V4 共享 DSP 基线比较。
#
# 当前默认配置：
#                  FPGA 型号：xc7a35tfgg484-2
#                  顶层模块：interp128_all2x_v4_shared_dsp_top_ce
#                  Stage 1 ：strict-halfband BRAM 单 DSP
#                  Stage 2/3：共享 DSP、统一 Q15、单舍入器
#                  Stage 4～7：canonical Q4 shift-add
#                  时钟频率：5.6448MHz
#                  结果目录：alt_all2x_v5/vivado_results/
#                              q15_compact_rounder
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-12
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-12：新增 Phase 5 Q15 单舍入器综合脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set v2_src_dir [file join $src_dir all2x_v2]
set v3_src_dir [file join $src_dir all2x_v3]
set v4_src_dir [file join $src_dir all2x_v4]
set v5_src_dir [file join $src_dir all2x_v5]
set stage23_acc_w 42
if {[llength $argv] > 0} {
    set stage23_acc_w [lindex $argv 0]
}
set result_dir [file normalize [file join $script_dir .. \
    vivado_results q15_compact_acc${stage23_acc_w}]]

file mkdir $result_dir

read_verilog [list \
    [file join $src_dir interp2_ctrl_ce.v] \
    [file join $src_dir bridge_to_interp2_ce.v] \
    [file join $src_dir round_sat_q16_to24.v] \
    [file join $v5_src_dir round_sat_q15_compact_to24.v] \
    [file join $src_dir fir_core_symm_interp2_all2x.v] \
    [file join $src_dir fir_core_symm_interp2_stage1_mac.v] \
    [file join $src_dir interp2_top_symm_ce_all2x.v] \
    [file join $v2_src_dir bridge_valid_only_to_interp2_ce.v] \
    [file join $v2_src_dir interp2_halfband7_shiftadd_ce.v] \
    [file join $v2_src_dir interp2_all2x_v2_stage_select.v] \
    [file join $v3_src_dir interp2_stage1_strict_halfband_bram_ce.v] \
    [file join $v4_src_dir interp2_stage23_shared_dsp_ce.v] \
    [file join $v4_src_dir interp128_all2x_v4_shared_dsp_top_ce.v]]

set_property include_dirs [list $v2_src_dir $v3_src_dir $v4_src_dir \
    $v5_src_dir] \
    [current_fileset]

synth_design -top interp128_all2x_v4_shared_dsp_top_ce \
    -part xc7a35tfgg484-2 \
    -generic [list STAGE23_ACC_W=$stage23_acc_w]

create_clock -name clk_audio_5m6448 -period 177.154 [get_ports clk]

report_utilization -hierarchical -file \
    [file join $result_dir utilization_hierarchical.txt]
report_utilization -file \
    [file join $result_dir utilization_summary.txt]
set dsp_fid [open [file join $result_dir dsp_utilization.txt] w]
set dsp_cells [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
puts $dsp_fid "DSP48E1 count = [llength $dsp_cells]"
foreach dsp_cell $dsp_cells {
    puts $dsp_fid ""
    puts $dsp_fid "CELL = $dsp_cell"
    foreach property_name [lsort [list_property $dsp_cell]] {
        puts $dsp_fid "$property_name = \
            [get_property $property_name $dsp_cell]"
    }
}
close $dsp_fid
report_timing_summary -delay_type max -max_paths 10 -file \
    [file join $result_dir timing_summary.txt]
write_checkpoint -force [file join $result_dir post_synth.dcp]

puts "Phase 5 Q15 single-rounder synthesis completed."
