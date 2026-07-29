#=============================================================
# 文件名       : verify_ila_hardware_debughub100m.tcl
# 脚本名       : verify_ila_hardware_debughub100m
# 功能简述     : 下载100MHz Debug Hub修正版BIT/LTX，并自动检查
#                Hardware Manager实际枚举的ILA、Probe和采样深度。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado Hardware Manager
# 修订记录     :
#                2026-07-19：新增修正版ILA实板枚举检查。
#                2026-07-19：检查增加DAC和逐级采样率的23探针版本。
#                2026-07-19：检查增加独立100MHz测频的26探针版本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set report_dir [file join $script_dir reports_ila_dac_rate_freqmeter100m]
set bit_file [file join $report_dir \
    board_demo_competition_dac8_top_ila_dac_rate_freqmeter100m.bit]
set ltx_file [file join $report_dir \
    board_demo_competition_dac8_top_ila_dac_rate_freqmeter100m.ltx]

open_hw
connect_hw_server -url localhost:3121

set hw_target [lindex [get_hw_targets -quiet *Digilent*] 0]
if {$hw_target eq ""} {
    error "No Digilent hardware target found"
}

open_hw_target $hw_target
set hw_device [lindex [get_hw_devices -quiet xc7a35t_0] 0]
if {$hw_device eq ""} {
    error "xc7a35t_0 was not detected"
}

set_property PROGRAM.FILE $bit_file $hw_device
set_property PROBES.FILE $ltx_file $hw_device
set_property FULL_PROBES.FILE $ltx_file $hw_device
program_hw_devices $hw_device
refresh_hw_device $hw_device

set hw_ilas [get_hw_ilas -quiet -of_objects $hw_device]
if {[llength $hw_ilas] != 1} {
    error "Expected one ILA core, got: $hw_ilas"
}

set hw_ila [lindex $hw_ilas 0]
set hw_probes [get_hw_probes -quiet -of_objects $hw_ila]
set data_depth [get_property CONTROL.DATA_DEPTH $hw_ila]

puts "ILA_HARDWARE_RESULT target=$hw_target device=$hw_device ila=$hw_ila probes=[llength $hw_probes] depth=$data_depth"

if {[llength $hw_probes] != 26} {
    error "Expected 26 ILA probes, got [llength $hw_probes]"
}
if {$data_depth != 4096} {
    error "Expected ILA depth 4096, got $data_depth"
}

puts "PASS: hardware enumerated one ILA core with 26 probes and depth 4096"
close_hw_target
disconnect_hw_server
close_hw
exit
