#=============================================================
# 文件名       : board_demo_competition_dac8_top.xdc
# 对应顶层     : board_demo_competition_dac8_top
# 功能简述     : Artix-7 XC7A35T 赛方板 AD9708 DAC 的 44.1kHz
#                专用全 2x 插值演示约束文件。
#                本文件用于约束板上 20MHz 系统时钟、矩阵按键
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
#                2026-07-08：补充配置电压属性，并按 MMCM 输出管脚
#                            引用自动派生音频时钟。
#                2026-07-10：删除 48kHz MMCM 后同步移除双音频
#                            时钟组约束，保留单 44.1kHz 时钟家族。
# 其他描述     :
#                1. 当前 IO 表确认 clk_20M 管脚为 Y18。
#                2. 当前 IO 表确认矩阵按键：
#                   KR0~KR3 = W21、R19、T20、P19；
#                   KC0~KC3 = T21、U21、V22、W22。
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
#                4. BEEP-IO = AB18，低电平响，高电平关闭。
#                5. SW1/SW2/SW3 和 SW5/SW6/SW7 均映射为
#                   44.1kHz 家族 4x/8x/128x 模式选择。
#=============================================================


#=============================================================
# 1）系统时钟约束
#
# clk：
#   板载 20MHz 系统时钟。
#
# 说明：
#   顶层内部结构为：
#     clk -> IBUF -> BUFG -> clk_sys_bufg
#   然后 clk_sys_bufg 送入 44.1kHz Clock Wizard。
#=============================================================
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

create_clock -period 50.000 -name clk_20M [get_ports clk]


#=============================================================
# 1.1）配置 Bank 电压属性
#
# 当前板级 IO 约束均采用 LVCMOS33，因此配置电压按 3.3V
# 工程属性给出，用于消除 Vivado CFGBVS/CONFIG_VOLTAGE
# DRC 提示。
#=============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]


#=============================================================
# 2）矩阵按键约束
#
# key_kr[3:0]：
#   KR0~KR3，扫描输出。顶层只主动拉低当前扫描列，
#   其他列保持高阻。
#
# key_kc[3:0]：
#   KC0~KC3，按键输入。原理图上每路已有 10k 上拉，
#   这里再使能 FPGA 弱上拉，避免连线悬空时漂移。
#=============================================================
set_property PACKAGE_PIN W21 [get_ports {key_kr[0]}]
set_property PACKAGE_PIN R19 [get_ports {key_kr[1]}]
set_property PACKAGE_PIN T20 [get_ports {key_kr[2]}]
set_property PACKAGE_PIN P19 [get_ports {key_kr[3]}]

set_property PACKAGE_PIN T21 [get_ports {key_kc[0]}]
set_property PACKAGE_PIN U21 [get_ports {key_kc[1]}]
set_property PACKAGE_PIN V22 [get_ports {key_kc[2]}]
set_property PACKAGE_PIN W22 [get_ports {key_kc[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {key_kr[*]}]
set_property DRIVE 8 [get_ports {key_kr[*]}]
set_property SLEW SLOW [get_ports {key_kr[*]}]

set_property IOSTANDARD LVCMOS33 [get_ports {key_kc[*]}]
set_property PULLUP true [get_ports {key_kc[*]}]


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
# 5）蜂鸣器静音输出约束
#
# BEEP-IO：
#   对应板卡蜂鸣器控制脚 AB18。
#   原理图为 PNP 高边驱动，BEEP-IO 拉低时蜂鸣器导通，
#   因此顶层固定输出高电平用于关闭蜂鸣器。
#=============================================================
set_property PACKAGE_PIN AB18 [get_ports beep_io]
set_property IOSTANDARD LVCMOS33 [get_ports beep_io]
set_property DRIVE 8 [get_ports beep_io]
set_property SLEW SLOW [get_ports beep_io]
set_property PULLUP true [get_ports beep_io]


#=============================================================
# 6）人工输入 false path 约束
#
# key_kc[3:0] 来自矩阵按键，属于人工慢速输入。
#
# 这些信号不是高速同步数据输入，顶层会在 20MHz 时钟域内
# 进行同步和消抖，因此这里设置 false path。
#=============================================================
set_false_path -from [get_ports {key_kc[*]}]


#=============================================================
# 7）控制域与音频域异步时钟组
#
# 当前只保留由 20MHz 输入经 clk_wiz_audio_44k1 派生的
# 5.6448MHz 音频时钟。模式控制使用两级同步器跨入音频域，
# 上电复位使用异步置位、同步释放结构，因此两个逻辑时钟域
# 之间不做同步时序收敛。
#=============================================================

set_clock_groups -asynchronous \
    -group [get_clocks clk_20M] \
    -group [get_clocks clk_audio_128x_44k1]
