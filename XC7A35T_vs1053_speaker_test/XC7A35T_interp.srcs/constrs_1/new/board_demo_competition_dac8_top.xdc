#=============================================================
# 文件名       : vs1053_sine_test_top.xdc
# 对应顶层     : vs1053_sine_test_top
# 功能简述     : Artix-7 XC7A35T 赛方板 / 自制板 VS1053
#                正弦测试工程约束文件。
#
#                本文件用于约束板载 50MHz 系统时钟以及
#                VS1053 SPI 控制接口。
#
# 当前工程功能 :
#                FPGA 通过 SPI 初始化 VS1053；
#                发送 VS1053 内置 sine test 命令；
#                VS1053 PHONE / 耳机输出端发出测试音。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-06-21
# 版本         : V2018.3
# 开发工具     : Vivado
#
# 说明         :
#                1. 当前顶层模块为 vs1053_sine_test_top。
#                2. 当前最小测试版本不使用 vs_miso。
#                3. 当前工程不约束 sw0/sw1/sw2、dac_clk、dac_data。
#                4. 当前工程不需要双 MMCM 时钟组约束。
#=============================================================


#=============================================================
# 1）系统时钟约束
#
# clk：
#   板载 50MHz 系统时钟。
#=============================================================
set_property PACKAGE_PIN R4 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

create_clock -period 20.000 -name clk_50M [get_ports clk]


#=============================================================
# 2）VS1053 SPI 时钟输出
#
# vs_sclk：
#   FPGA 输出到 VS1053 的 SPI 时钟。
#
# 对应连接：
#   VS_CLK / VS_SCK
#=============================================================
set_property PACKAGE_PIN W15 [get_ports vs_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports vs_sclk]
set_property DRIVE 8 [get_ports vs_sclk]
set_property SLEW SLOW [get_ports vs_sclk]


#=============================================================
# 3）VS1053 SPI MOSI 输出
#
# vs_mosi：
#   FPGA 输出到 VS1053 的 SPI 数据。
#
# 对应连接：
#   VS_MOSI
#=============================================================
set_property PACKAGE_PIN E13 [get_ports vs_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports vs_mosi]
set_property DRIVE 8 [get_ports vs_mosi]
set_property SLEW SLOW [get_ports vs_mosi]


#=============================================================
# 4）VS1053 SCI 控制接口片选
#
# vs_xcs_n：
#   VS1053 控制寄存器接口片选，低有效。
#
# 对应连接：
#   VS_XCS
#=============================================================
set_property PACKAGE_PIN Y22 [get_ports vs_xcs_n]
set_property IOSTANDARD LVCMOS33 [get_ports vs_xcs_n]
set_property DRIVE 8 [get_ports vs_xcs_n]
set_property SLEW SLOW [get_ports vs_xcs_n]


#=============================================================
# 5）VS1053 DREQ 输入
#
# vs_dreq：
#   VS1053 数据请求信号。
#   高电平表示 VS1053 可以接收新的控制命令或数据。
#
# 对应连接：
#   VS_DREQ
#=============================================================
set_property PACKAGE_PIN AB21 [get_ports vs_dreq]
set_property IOSTANDARD LVCMOS33 [get_ports vs_dreq]


#=============================================================
# 6）VS1053 复位输出
#
# vs_rst_n：
#   VS1053 复位信号，低有效。
#
# 对应连接：
#   VS_RST
#=============================================================
set_property PACKAGE_PIN AB20 [get_ports vs_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports vs_rst_n]
set_property DRIVE 8 [get_ports vs_rst_n]
set_property SLEW SLOW [get_ports vs_rst_n]


#=============================================================
# 7）VS1053 SDI 音频数据接口片选
#
# vs_xdcs_n：
#   VS1053 音频数据接口片选，低有效。
#   sine test 命令通过该接口发送。
#
# 对应连接：
#   VS_XDCS
#=============================================================
set_property PACKAGE_PIN AB22 [get_ports vs_xdcs_n]
set_property IOSTANDARD LVCMOS33 [get_ports vs_xdcs_n]
set_property DRIVE 8 [get_ports vs_xdcs_n]
set_property SLEW SLOW [get_ports vs_xdcs_n]


#=============================================================
# 8）异步输入 false path
#
# vs_dreq：
#   来自 VS1053 的外部状态信号，不是由 FPGA clk_50M
#   同步产生的内部数据路径。
#=============================================================
set_false_path -from [get_ports vs_dreq]


#=============================================================
# 9）配置电压属性
#
# 说明：
#   如果你的开发板配置 Bank 电压为 3.3V，
#   可以保留下面两句，用于消除 CFGBVS / CONFIG_VOLTAGE 警告。
#   如果你的板卡手册明确写了配置电压不是 3.3V，
#   则需要按手册修改 CONFIG_VOLTAGE。
#=============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
