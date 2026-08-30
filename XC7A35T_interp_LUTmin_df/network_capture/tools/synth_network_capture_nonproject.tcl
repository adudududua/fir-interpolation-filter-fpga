# 对现有竞赛顶层执行非工程模式综合与约束检查。
# 当用户级 Vivado Tcl 扩展库阻碍 .xpr 图形界面流程时，可使用此脚本。
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. ..]]
set src_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set net_root [file join $project_dir network_capture rtl]
set result_dir [file join $project_dir network_capture results synth_nonproject]
file mkdir $result_dir

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
# 把只有宏定义的头文件先作为全局头读入；这样纯非工程模式无需依赖
# current_fileset.include_dirs，也能编译其他目录中的 `include`。
set coeff_v2 [file join $src_root all2x_v2 all2x_v2_coeff_pkg.vh]
set coeff_v3 [file join $src_root all2x_v3 all2x_v3_stage1_coeff_pkg.vh]
if {[file exists $coeff_v2]} { read_verilog $coeff_v2 }
if {[file exists $coeff_v3]} { read_verilog $coeff_v3 }
# 工程源文件是 Verilog-2001；其中协议端口名 sequence 在 SystemVerilog 中
# 是保留字，因此这里不能强制按 -sv 解析。
read_verilog $rtl_files

synth_design -top board_demo_competition_dac8_top \
    -part xc7a35tfgg484-2 -flatten_hierarchy rebuilt
read_xdc [file join $project_dir XC7A35T_interp.srcs constrs_1 new \
    board_demo_competition_dac8_top.xdc]

report_utilization -file [file join $result_dir utilization_synth.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir timing_synth.rpt]
report_drc -file [file join $result_dir drc_synth.rpt]
write_checkpoint -force [file join $result_dir board_network_synth.dcp]
puts "NETWORK_CAPTURE_SYNTH_PASS"
