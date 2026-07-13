#=============================================================
# 文件名       : synth_phase6_three_dsp_pareto.tcl
# 脚本名       : synth_phase6_three_dsp_pareto
# 功能简述     : 对 Phase 6 三 DSP 独立 Stage2/3 候选链执行
#                独立综合，导出总资源、层次资源、DSP 映射、
#                时序和检查点，供 2 DSP / 3 DSP Pareto 比较。
#
# 当前默认配置：
#                  FPGA 型号：xc7a35tfgg484-2
#                  顶层模块：interp128_all2x_v6_three_dsp_top_ce
#                  Stage 1 ：strict-halfband BRAM 单 DSP
#                  Stage 2 ：独立串行 DSP MAC
#                  Stage 3 ：独立串行 DSP MAC
#                  Stage 4～7：canonical Q4 shift-add
#                  时钟频率：5.6448MHz
#                  累加位宽：40bit
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-13
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-13：新增 Phase 6 三 DSP Pareto 综合脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set v2_src_dir [file join $src_dir all2x_v2]
set v3_src_dir [file join $src_dir all2x_v3]
set v5_src_dir [file join $src_dir all2x_v5]
set v6_src_dir [file join $src_dir all2x_v6]
set result_dir [file normalize [file join $script_dir .. \
    vivado_results three_dsp_acc40]]
set temp_project_dir [file normalize [file join $script_dir .. \
    vivado_work phase6_three_dsp_project_[pid]]]

file mkdir $result_dir

set source_files [list \
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
    [file join $v6_src_dir interp2_stage23_independent_dsp_ce.v] \
    [file join $v6_src_dir interp128_all2x_v6_three_dsp_top_ce.v]]

create_project phase6_three_dsp_pareto $temp_project_dir \
    -part xc7a35tfgg484-2 -force
add_files -norecurse $source_files

set_property include_dirs [list $v2_src_dir $v3_src_dir $v5_src_dir \
    $v6_src_dir] [get_filesets sources_1]
set_property top interp128_all2x_v6_three_dsp_top_ce \
    [get_filesets sources_1]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 6 three-DSP synthesis did not complete."
}

open_run synth_1

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

puts "Phase 6 three-DSP Pareto synthesis completed."
close_project
