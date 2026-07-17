#=============================================================
# 文件名       : generate_phase7_stable_mcs.tcl
# 脚本名       : generate_phase7_stable_mcs
# 功能简述     : 将已恢复并重新实现的 Phase 7 0.50FS 稳定版
#                bitstream
#                转换为板载 SPI Flash 使用的 MCS 配置文件。
#                采用保守的 SPI x1 接口和 128 Mbit 容量，
#                适用于支持 x1/x2/x4 的 MT25QL128 配置存储器。
#
# 当前默认配置：
#                  输入格式：BIT
#                  输出格式：MCS
#                  起始地址：0x00000000
#                  SPI 接口：x1
#                  Flash 容量：128 Mbit
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-17
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-17：新增 Phase 7 稳定版 MCS 生成脚本。
#                2026-07-17：输入改为 0.50FS 削顶诊断版。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set result_root [file normalize [file join $script_dir .. vivado_results]]
set bit_file [file join $result_root board_folded_n3 \
    board_demo_competition_dac8_top_phase7_folded_n3_amp050.bit]
set output_dir [file join $result_root config_memory]
set mcs_file [file join $output_dir \
    phase7_stable_rebuilt_amp050_spi_x1.mcs]

if {![file exists $bit_file]} {
    error "Phase 7 stable bitstream does not exist: $bit_file"
}

file mkdir $output_dir

write_cfgmem -force \
    -format mcs \
    -interface SPIx1 \
    -size 128 \
    -loadbit [format {up 0x00000000 %s} $bit_file] \
    -file $mcs_file

puts "Phase 7 stable MCS generation completed."
puts "Input BIT : $bit_file"
puts "Output MCS: $mcs_file"
