# 对带 DAC24 以太网采集功能的竞赛顶层执行完整的非工程模式构建。
# 生成布线后检查点、实现报告和板级比特流。
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. ..]]
set src_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set net_root [file join $project_dir network_capture rtl]
set result_dir [file join $project_dir network_capture results implementation]
file mkdir $result_dir

# 这台联调电脑为 16 GB 内存；限制并行线程可显著降低综合/实现峰值提交量，
# 避免在 write_bitstream 阶段因 Windows 页面文件接近上限而退出。
set_param general.maxThreads 2

proc recursive_files {root pattern} {
    set result {}
    foreach entry [glob -nocomplain -directory $root *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [recursive_files $entry $pattern]]
        } elseif {[string match $pattern [file tail $entry]]} {
            lappend result $entry
        }
    }
    return $result
}

set include_dirs [list \
    [file join $src_root all2x_v2] \
    [file join $src_root all2x_v3] \
    [file join $src_root all2x_v4] \
    [file join $src_root all2x_v5] \
    [file join $src_root all2x_v6] \
    [file join $src_root all2x_v7]]

set rtl_files [recursive_files $src_root *.v]
foreach file [recursive_files $net_root *.v] {
    lappend rtl_files $file
}
# 先把全局宏头读入，避免依赖 current_fileset.include_dirs。
set coeff_v2 [file join $src_root all2x_v2 all2x_v2_coeff_pkg.vh]
set coeff_v3 [file join $src_root all2x_v3 all2x_v3_stage1_coeff_pkg.vh]
if {[file exists $coeff_v2]} { read_verilog $coeff_v2 }
if {[file exists $coeff_v3]} { read_verilog $coeff_v3 }
read_verilog $rtl_files

synth_design -top board_demo_competition_dac8_top \
    -part xc7a35tfgg484-2 -flatten_hierarchy rebuilt
read_xdc [file join $project_dir XC7A35T_interp.srcs constrs_1 new \
    board_demo_competition_dac8_top.xdc]

opt_design
place_design
phys_opt_design
route_design

report_utilization -file [file join $result_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 50 \
    -file [file join $result_dir timing_routed.rpt]
report_bus_skew -file [file join $result_dir bus_skew_routed.rpt]
report_clock_interaction -file [file join $result_dir clock_interaction.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
report_io -file [file join $result_dir io_routed.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min -slack_lesser_than 0]
if {[llength $setup_paths] != 0 || [llength $hold_paths] != 0} {
    error "NETWORK_CAPTURE_IMPLEMENT_TIMING_FAILED: [llength $setup_paths] 条建立时间路径和 [llength $hold_paths] 条保持时间路径存在负裕量"
}

write_checkpoint -force [file join $result_dir board_network_routed.dcp]
write_bitstream -force [file join $result_dir board_network.bit]
puts "NETWORK_CAPTURE_IMPLEMENT_PASS"
