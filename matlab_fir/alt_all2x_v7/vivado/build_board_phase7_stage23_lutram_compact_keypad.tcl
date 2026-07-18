#=============================================================
# 文件名       : build_board_phase7_stage23_lutram_compact_keypad.tcl
# 脚本名       : build_board_phase7_stage23_lutram_compact_keypad
# 功能简述     : 构建 Stage 2/3 单读 LUTRAM 与紧凑矩阵键盘候选。
#                滤波器算法、0.50FS 正弦、定点字长和四档 DAC
#                数据路径保持不变；CIC burst 计数器可在 DSP 与
#                LUT 进位链之间 A/B。矩阵键盘仅保留
#                SW1～SW8 的两行重复四档映射，并继续执行输入同步
#                和整轮扫描消抖，以减少完整 16 键位图控制逻辑。
#
#                脚本完成综合、实现、bitstream，并导出层级资源、
#                原语、时序、时钟交互、功耗、DRC 与方法学报告。
#                所有结果写入独立目录，不覆盖稳定版本和 578 LUT
#                Stage 2/3 LUTRAM 基线。
#
# 当前默认配置：
#                  工程顶层：board_demo_competition_dac8_top
#                  工作模式：1x / 4x / 8x / 128x
#                  插值结构：2x x 2x x 2x x CIC16
#                  Stage 2/3：单读 LUTRAM + 1 个共享 DSP48E1
#                  矩阵按键：SW1～SW8 紧凑扫描与消抖
#                  tclargs 0：Stage 2/3 历史缓存使用 LUTRAM
#                  tclargs 1：Stage 2/3 历史缓存使用双口 BRAM
#                  第二参数 1：顺序系数表使用同步 BRAM
#                  第三参数 1：紧凑键盘扫描分频使用 16384
#                  第四参数 1：复用上电计数器产生键盘扫描使能
#                  第五参数 1：启用面积优先综合与逻辑优化 directive
#                  第六参数 1：CIC burst 计数器使用 LUT 进位链；
#                              设为 0 可重建原 9-DSP 对照
#                  目标器件：xc7a35tfgg484-2
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-18
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-18：新增紧凑矩阵键盘板级构建脚本。
#                2026-07-18：增加可选 BRAM 历史缓存构建参数。
#                2026-07-18：增加可选二次幂键盘扫描分频构建参数。
#                2026-07-18：增加可选上电计数器复用扫描构建参数。
#                2026-07-18：增加可选 Vivado 面积优先策略 A/B 参数。
#                2026-07-18：增加 CIC burst 计数器 LUT 候选结果隔离。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set common_src_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs sources_1 new]
set v7_src_dir [file join $common_src_dir all2x_v7]
set stage23_lutram_src [file join $v7_src_dir interp2_stage23_lutram_cic_dsp_ce.v]
set compact_keypad_src [file join $common_src_dir matrix_keypad_mode_ctrl_compact.v]

set use_bram_history 0
set use_bram_coeff 0
set use_pow2_keypad_scan 0
set use_shared_keypad_scan_tick 0
set use_area_directive 0
set use_lut_burst_counter_candidate 0
if {$argc > 0} {
    set use_bram_history [lindex $argv 0]
}
if {$argc > 1} {
    set use_bram_coeff [lindex $argv 1]
}
if {$argc > 2} {
    set use_pow2_keypad_scan [lindex $argv 2]
}
if {$argc > 3} {
    set use_shared_keypad_scan_tick [lindex $argv 3]
}
if {$argc > 4} {
    set use_area_directive [lindex $argv 4]
}
if {$argc > 5} {
    set use_lut_burst_counter_candidate [lindex $argv 5]
}
if {$use_bram_history != 0 && $use_bram_history != 1} {
    error "BRAM history selector must be 0 or 1."
}
if {$use_bram_coeff != 0 && $use_bram_coeff != 1} {
    error "BRAM coefficient selector must be 0 or 1."
}
if {$use_pow2_keypad_scan != 0 && $use_pow2_keypad_scan != 1} {
    error "Power-of-two keypad scan selector must be 0 or 1."
}
if {$use_shared_keypad_scan_tick != 0 && $use_shared_keypad_scan_tick != 1} {
    error "Shared keypad scan selector must be 0 or 1."
}
if {$use_area_directive != 0 && $use_area_directive != 1} {
    error "Area directive selector must be 0 or 1."
}
if {$use_lut_burst_counter_candidate != 0 &&
    $use_lut_burst_counter_candidate != 1} {
    error "LUT burst counter candidate selector must be 0 or 1."
}
set cic_burst_counter_use_dsp [expr {
    $use_lut_burst_counter_candidate != 0 ? 0 : 1}]

if {$use_pow2_keypad_scan != 0} {
    set keypad_scan_div 16384
    set keypad_suffix _pow2scan
} else {
    set keypad_scan_div 20000
    set keypad_suffix ""
}
if {$use_shared_keypad_scan_tick != 0} {
    append keypad_suffix _sharedscan
}
if {$use_area_directive != 0} {
    append keypad_suffix _areaopt
}
if {$use_lut_burst_counter_candidate != 0} {
    append keypad_suffix _dsp8
}

if {$use_bram_history != 0 && $use_bram_coeff != 0} {
    set result_name board_folded_n3_stage23_bram_coeff_compact_keypad${keypad_suffix}
    set bitstream_name board_demo_competition_dac8_top_phase7_stage23_bram_coeff_compact_keypad${keypad_suffix}_amp050.bit
} elseif {$use_bram_history != 0} {
    set result_name board_folded_n3_stage23_bram_compact_keypad${keypad_suffix}
    set bitstream_name board_demo_competition_dac8_top_phase7_stage23_bram_compact_keypad${keypad_suffix}_amp050.bit
} else {
    set result_name board_folded_n3_stage23_lutram_compact_keypad${keypad_suffix}
    set bitstream_name board_demo_competition_dac8_top_phase7_stage23_lutram_compact_keypad${keypad_suffix}_amp050.bit
}
if {$use_area_directive != 0} {
    if {$use_lut_burst_counter_candidate != 0} {
        set bitstream_name phase7_bram_sharedscan_areaopt_dsp8_amp050.bit
    } else {
        set bitstream_name phase7_bram_sharedscan_areaopt_amp050.bit
    }
}
set result_dir [file normalize [file join $script_dir .. vivado_results $result_name]]

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

foreach source_file [list $stage23_lutram_src $compact_keypad_src] {
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
    }
}

set_property top board_demo_competition_dac8_top [get_filesets sources_1]
set generic_values [list \
    USE_PHASE7_LUTRAM_STAGE23=1 \
    USE_COMPACT_KEYPAD=1 \
    [format "COMPACT_KEYPAD_SCAN_DIV=%d" $keypad_scan_div] \
    [format "USE_SHARED_KEYPAD_SCAN_TICK=%d" $use_shared_keypad_scan_tick] \
    [format "USE_PHASE7_BRAM_STAGE23_HISTORY=%d" $use_bram_history] \
    [format "USE_PHASE7_BRAM_STAGE23_COEFF=%d" $use_bram_coeff] \
    [format "USE_PHASE7_CIC_BURST_COUNTER_DSP=%d" \
        $cic_burst_counter_use_dsp]]
set_property generic $generic_values [get_filesets sources_1]
update_compile_order -fileset sources_1

if {$use_area_directive != 0} {
    set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea [get_runs impl_1]
} else {
    set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Default [get_runs synth_1]
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
}

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Phase 7 compact keypad synthesis did not complete."
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Phase 7 compact keypad implementation did not complete."
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
    "DSP48*" "Phase 7 compact keypad DSP utilization"
write_primitive_report [file join $result_dir bram_utilization_routed.rpt] \
    "RAMB*" "Phase 7 compact keypad BRAM utilization"
write_primitive_report [file join $result_dir lutram_utilization_routed.rpt] \
    "RAMD*" "Phase 7 compact keypad distributed RAM utilization"
report_power -file [file join $result_dir power_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
catch {
    report_methodology -file [file join $result_dir methodology_routed.rpt]
}
catch {
    report_cdc -details -file [file join $result_dir cdc_routed.rpt]
}
write_checkpoint -force [file join $result_dir board_phase7_compact_keypad_routed.dcp]

set bitstream_src [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.runs impl_1 board_demo_competition_dac8_top.bit]
if {![file exists $bitstream_src]} {
    error "Phase 7 compact keypad bitstream was not generated."
}
file copy -force $bitstream_src \
    [file join $result_dir $bitstream_name]

puts "Phase 7 Stage 2/3 LUTRAM compact keypad board build completed."
close_project
