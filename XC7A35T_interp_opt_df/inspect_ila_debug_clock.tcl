#=============================================================
# 文件名       : inspect_ila_debug_clock.tcl
# 脚本名       : inspect_ila_debug_clock
# 功能简述     : 检查已实现设计中 ILA 与 Debug Hub 的实际时钟连接
#                和调试核参数，用于定位 Hardware Manager 枚举异常。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-19：新增 ILA 调试时钟检查脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set inspect_mode [expr {$argc > 0 ? [lindex $argv 0] : "routed"}]
set inspect_synth [expr {$inspect_mode eq "synth" || $inspect_mode eq "hooktest"}]
if {$inspect_synth} {
    set routed_dcp [file join $script_dir XC7A35T_interp.runs synth_1 \
        board_demo_competition_dac8_top.dcp]
} else {
    set routed_dcp [file join $script_dir XC7A35T_interp.runs impl_1 \
        board_demo_competition_dac8_top_routed.dcp]
}

open_checkpoint $routed_dcp

if {$inspect_mode eq "hooktest"} {
    source [file join $script_dir configure_ila_debug_hub_100m.tcl]
}

puts "ILA_DEBUG_CORES_BEGIN"
foreach debug_core [get_debug_cores] {
    puts "core=$debug_core"
    foreach property_name {
        C_CLK_INPUT_FREQ_HZ
        C_ENABLE_CLK_DIVIDER
        C_USER_SCAN_CHAIN
        C_DATA_DEPTH
        C_NUM_OF_PROBES
    } {
        set property_value [get_property -quiet $property_name $debug_core]
        if {$property_value ne ""} {
            puts "  $property_name=$property_value"
        }
    }
}
puts "ILA_DEBUG_CORES_END"

foreach pin_name {dbg_hub/clk u_ila_image_rejection/clk} {
    set debug_pin [get_pins -quiet $pin_name]
    if {[llength $debug_pin] == 0} {
        puts "DEBUG_CLOCK pin=$pin_name missing"
    } else {
        set debug_net [get_nets -quiet -of_objects $debug_pin]
        set debug_clocks [get_clocks -quiet -of_objects $debug_pin]
        puts "DEBUG_CLOCK pin=$pin_name net=$debug_net clocks=$debug_clocks"
    }
}

close_design
exit
