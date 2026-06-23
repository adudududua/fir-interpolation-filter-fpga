#=============================================================
# 文件名       : board_demo_competition_dac8_top.xdc
# 对应顶层     : board_demo_competition_dac8_top
# 功能简述     : Artix-7 XC7A35T 赛方板 AD9708 DAC 双频率家族
#                插值演示约束文件。
#                本文件用于约束板上 50MHz 系统时钟、拨码开关
#                以及 AD9708 8bit 并行 DAC 接口。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-06-19
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-06-19：整理为 AD9708 DAC 最小约束版本。
#                2026-06-19：删除 XDC 内残留 ILA debug core 约束。
#                2026-06-20：修正为双频率家族正式演示版本说明。
#                2026-06-20：不使用 CLOCK_DEDICATED_ROUTE FALSE。
#                2026-06-20：当前顶层无外部 rst_n 端口，因此不约束 rst_n。
# 其他描述     :
#                1. 当前 IO 表确认 clk_50M 管脚为 R4。
#                2. 当前 IO 表确认 SW0、SW1、SW2 分别为
#                   W19、AA21、AA19。
#                3. 当前 IO 表确认 AD9708 接口：
#                   DA_CLK = G16；
#                   DA_D0  = H19；
#                   DA_D1  = E19；
#                   DA_D2  = H18；
#                   DA_D3  = G18；
#                   DA_D4  = F18；
#                   DA_D5  = G17；
#                   DA_D6  = E17；
#                   DA_D7  = C17。
#                4. sw2 = 0 时选择 44.1kHz 家族；
#                   sw2 = 1 时选择 48kHz 家族。
#=============================================================


#=============================================================
# 1）系统时钟约束
#
# clk：
#   板载 50MHz 系统时钟。
#
# 说明：
#   顶层内部结构为：
#     clk -> IBUF -> BUFG -> clk_sys_bufg
#   然后 clk_sys_bufg 同时送入两个 Clock Wizard。
#=============================================================
set_property PACKAGE_PIN R4 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

create_clock -period 20.000 -name clk_50M [get_ports clk]


#=============================================================
# 2）拨码开关约束
#
# sw0：
#   插值倍率选择低位。
#
# sw1：
#   插值倍率选择高位。
#
# sw2：
#   频率家族选择。
#   sw2 = 0：选择 44.1kHz 家族；
#   sw2 = 1：选择 48kHz 家族。
#=============================================================
set_property PACKAGE_PIN W19  [get_ports sw0]
set_property PACKAGE_PIN AA21 [get_ports sw1]
set_property PACKAGE_PIN AA19 [get_ports sw2]

set_property IOSTANDARD LVCMOS33 [get_ports sw0]
set_property IOSTANDARD LVCMOS33 [get_ports sw1]
set_property IOSTANDARD LVCMOS33 [get_ports sw2]


#=============================================================
# 3）AD9708 DAC 采样时钟约束
#
# dac_clk：
#   输出给 AD9708 的 DA_CLK。
#
# 不同模式下理论频率：
#   44.1kHz 家族：
#     4x   ：约 176.4kHz；
#     8x   ：约 352.8kHz；
#     128x ：约 5.6448MHz。
#
#   48kHz 家族：
#     4x   ：约 192kHz；
#     8x   ：约 384kHz；
#     128x ：约 6.144MHz。
#=============================================================
set_property PACKAGE_PIN G16 [get_ports dac_clk]
set_property IOSTANDARD LVCMOS33 [get_ports dac_clk]
set_property DRIVE 8 [get_ports dac_clk]
set_property SLEW FAST [get_ports dac_clk]


#=============================================================
# 4）AD9708 DAC 8bit 并行数据约束
#
# 对应关系：
#   dac_data[0] -> DA_D0 -> H19；
#   dac_data[1] -> DA_D1 -> E19；
#   dac_data[2] -> DA_D2 -> H18；
#   dac_data[3] -> DA_D3 -> G18；
#   dac_data[4] -> DA_D4 -> F18；
#   dac_data[5] -> DA_D5 -> G17；
#   dac_data[6] -> DA_D6 -> E17；
#   dac_data[7] -> DA_D7 -> C17。
#
# 注意：
#   之前测到 DA_D5 未接到板子上，现在硬件已经接好，
#   因此这里仍保持 dac_data[5] -> G17。
#=============================================================
set_property PACKAGE_PIN H19 [get_ports {dac_data[0]}]
set_property PACKAGE_PIN E19 [get_ports {dac_data[1]}]
set_property PACKAGE_PIN H18 [get_ports {dac_data[2]}]
set_property PACKAGE_PIN G18 [get_ports {dac_data[3]}]
set_property PACKAGE_PIN F18 [get_ports {dac_data[4]}]
set_property PACKAGE_PIN G17 [get_ports {dac_data[5]}]
set_property PACKAGE_PIN E17 [get_ports {dac_data[6]}]
set_property PACKAGE_PIN C17 [get_ports {dac_data[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[*]}]
set_property DRIVE 8 [get_ports {dac_data[*]}]
set_property SLEW SLOW [get_ports {dac_data[*]}]


#=============================================================
# 5）人工输入 false path 约束
#
# sw0、sw1、sw2 来自拨码开关，属于人工慢速输入。
#
# sw0 / sw1：
#   只用于选择 4x、8x、128x 输出模式。
#
# sw2：
#   用于 BUFGMUX 选择 44.1kHz / 48kHz 家族。
#
# 这些信号不是高速同步数据输入，因此这里设置 false path。
#=============================================================
set_false_path -from [get_ports {sw0 sw1 sw2}]


#=============================================================
# 6）系统时钟与两个音频时钟的时钟组约束
#
# 目的：
#   当前顶层同时存在：
#     clk_50M 系统时钟；
#     clk_wiz_audio_44k1 输出的 5.6448MHz；
#     clk_wiz_audio_48k  输出的 6.144MHz。
#
#   两个音频时钟通过 BUFGMUX 选择后送入同一套 FIR 插值链。
#   sw2 选择其中一路工作，硬件上不会同时使用两路音频时钟。
#
#   如果不显式告诉 Vivado 这些时钟关系，route 阶段容易出现
#   大量不真实的 hold violation，导致布线时间极长甚至拥塞。
#
# 说明：
#   这里直接写 set_clock_groups，不使用 if，因为 Vivado 2018.3
#   的 XDC 文件不支持 if 控制语句。
#=============================================================

set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_50M] \
    -group [get_clocks -quiet -of_objects [get_pins u_clk_wiz_audio_44k1/inst/mmcm_adv_inst/CLKOUT0]] \
    -group [get_clocks -quiet -of_objects [get_pins u_clk_wiz_audio_48k/inst/mmcm_adv_inst/CLKOUT0]]