#=============================================================
# 文件名       : board_demo_competition_dac8_top.xdc
# 对应顶层     : board_demo_competition_dac8_top
# 功能简述     : Artix-7 XC7A35T 全国赛 44.1/48 kHz 双采样率、
#                4x/8x/128x AD9708 插值演示约束文件。
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
#                5. SW1～SW4 映射 44.1 kHz 的 1x/4x/8x/128x；
#                   SW5～SW8 映射 48 kHz 的 1x/4x/8x/128x。
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
#   然后 clk_sys_bufg 同时送入两颗 MMCM，专用 BUFGMUX_CTRL
#   选择当前 5.6448/6.144 MHz 音频时钟。
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

# 对两个互斥采样率家族的 ODDR 转发时钟路径建模。
# 低速模式只是减少时钟边沿，因此 128x 时钟可作为四种 DAC 模式的
# 保守主时钟。
set nf_clk_44k1 [get_clocks -of_objects \
    [get_pins u_dual_family_audio_clock/u_mmcm_44k1/CLKOUT0]]
set nf_clk_48k [get_clocks -of_objects \
    [get_pins u_dual_family_audio_clock/u_mmcm_48k/CLKOUT0]]
set nf_dac_oddr_c [get_pins \
    u_demo_interp_dac8_audio_pcm_common/gen_dac_clock_oddr.u_dac_clock_oddr/C]

create_generated_clock -name dac_clk_44k1_128x \
    -source $nf_dac_oddr_c -master_clock $nf_clk_44k1 -divide_by 1 -add \
    [get_ports dac_clk]
create_generated_clock -name dac_clk_48k_128x \
    -source $nf_dac_oddr_c -master_clock $nf_clk_48k -divide_by 1 -add \
    [get_ports dac_clk]

# AD9708 在 DAC_CLK 上升沿采样。器件最坏要求为 tS=2.0 ns、tH=1.5 ns；
# 另加入保守的 0.5 ns PCB/封装偏斜预算。128x 时钟最快，因此其约束也
# 覆盖所有低速模式。
set nf_dac_clk_44k1 [get_clocks dac_clk_44k1_128x]
set nf_dac_clk_48k [get_clocks dac_clk_48k_128x]
set_output_delay -clock $nf_dac_clk_44k1 -max 2.500 \
    [get_ports {dac_data[*]}]
set_output_delay -clock $nf_dac_clk_44k1 -min -2.000 \
    [get_ports {dac_data[*]}]
set_output_delay -clock $nf_dac_clk_48k -max 2.500 -add_delay \
    [get_ports {dac_data[*]}]
set_output_delay -clock $nf_dac_clk_48k -min -2.000 -add_delay \
    [get_ports {dac_data[*]}]


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
# 5.1）RTL8211E RGMII 以太网接口
#
# 根据场景板的电阻装配与 PHY 上下拉配置，该接口只能协商到
# 100BASE-TX。因此本设计转发固定的 25 MHz 发送时钟，并通过 FPGA
# 侧 MMCM 对 TXC 移相，以适配板上“TX/RX 无延时”的上下拉配置。
#=============================================================
set_property PACKAGE_PIN D14 [get_ports mac_rst]
set_property PACKAGE_PIN J14 [get_ports mac_intb]
set_property PACKAGE_PIN D17 [get_ports mac_rxclk]
set_property PACKAGE_PIN C13 [get_ports mac_rxctl]
set_property PACKAGE_PIN F13 [get_ports {mac_rxd[0]}]
set_property PACKAGE_PIN G13 [get_ports {mac_rxd[1]}]
set_property PACKAGE_PIN H13 [get_ports {mac_rxd[2]}]
set_property PACKAGE_PIN H14 [get_ports {mac_rxd[3]}]
set_property PACKAGE_PIN C18 [get_ports mac_txclk]
set_property PACKAGE_PIN H15 [get_ports mac_txctl]
set_property PACKAGE_PIN G15 [get_ports {mac_txd[0]}]
set_property PACKAGE_PIN C15 [get_ports {mac_txd[1]}]
set_property PACKAGE_PIN D15 [get_ports {mac_txd[2]}]
set_property PACKAGE_PIN C14 [get_ports {mac_txd[3]}]
set_property PACKAGE_PIN E14 [get_ports eth_mdc]
set_property PACKAGE_PIN E16 [get_ports eth_mdio]

set_property IOSTANDARD LVCMOS33 [get_ports {mac_rst mac_intb mac_rxclk mac_rxctl mac_rxd[*] mac_txclk mac_txctl mac_txd[*] eth_mdc eth_mdio}]
set_property DRIVE 8 [get_ports {mac_rst mac_txclk mac_txctl mac_txd[*] eth_mdc}]
set_property SLEW FAST [get_ports {mac_txclk mac_txctl mac_txd[*]}]
set_property PULLUP true [get_ports {mac_intb eth_mdio}]

create_clock -period 40.000 -name rgmii_rxclk_100m [get_ports mac_rxclk]

# 百兆 RGMII 接收端使用单沿 IOB 寄存器的下降沿样本。板上 PHY 配置为 RX NoDelay；
# 100M 半字节在 RXC 上升沿附近切换，并在 40 ns 周期内保持，下降沿样本位于
# 约 20 ns 后的数据眼中点。输入延时必须相对 PHY 的实际“上升沿发射”来描述，
# 不能把 -22/-18 ns 窗口挂在下降沿：那会把同一下降沿保持检查错误地变成
# 约 22 ns 的要求。这里用 ±2 ns 包络 PHY 时钟到输出、PCB 走线差和建模裕量；
# IOB 寄存器的下降沿捕获会由 STA 自然形成约 20 ns 的半周期建立/保持窗口。
# 布局后仍需结合 PHY 数据手册和板上实测的 RXC-RXD 偏斜复核这两个数值。
set_input_delay -clock rgmii_rxclk_100m -max 2.000 \
    [get_ports {mac_rxctl mac_rxd[*]}]
set_input_delay -clock rgmii_rxclk_100m -min -2.000 \
    [get_ports {mac_rxctl mac_rxd[*]}]

# 接收 RTL 只实例化下降沿寄存器，不产生无效的上升沿采样端点，因此这里不需要
# 任何 RGMII 数据 false path；5 条输入路径的建立/保持时间均由 STA 正常签核。
set_false_path -from [get_ports mac_intb]

# 采集请求和完成信号采用保持型翻转标志，并通过已标记的两级触发器链
# 进行同步。仅切除异步源到第一级触发器的路径；保持稳定的描述符总线
# 会在额外等待四个网络时钟后采样。
set nf_capture_toggle_sync_pins [get_pins -hierarchical -regexp \
    {.*u_dac24_udp_network/u_capture/(take_meta_reg|done_meta_reg)/D}]
set_false_path -to $nf_capture_toggle_sync_pins

# net_rst_n 在 25 MHz 网络时钟域内产生。采集复位同步器采用异步置位、
# 经两个已标记的音频域触发器同步释放；时序分析仅豁免异步清零路径。
set nf_capture_reset_async_pins [get_pins -hierarchical -regexp \
    {.*u_dac24_udp_network/capture_rst_sync_reg\[[01]\]/CLR}]
set_false_path -to $nf_capture_reset_async_pins

set nf_rx_reset_async_pins [get_pins -hierarchical -regexp \
    {.*u_dac24_udp_network/rx_rst_sync_reg\[[01]\]/CLR}]
set_false_path -to $nf_rx_reset_async_pins

set nf_network_reset_async_pins [get_pins -hierarchical -regexp \
    {.*net_rst_sync_reg\[[01]\]/CLR}]
set_false_path -to $nf_network_reset_async_pins

set nf_rgmii_txc_reset_async_pins [get_pins -hierarchical -regexp \
    {.*u_dac24_udp_network/u_rgmii_tx/txc_rst_sync_reg\[[01]\]/CLR}]
set_false_path -to $nf_rgmii_txc_reset_async_pins

# UDP 上传控制采用“翻转事件 + 稳定描述符”从 PHY 接收时钟域跨到当前音频时钟域。
# 这里只对翻转同步器第一级的 D 引脚设置 false path，第二级仍保留正常的单时钟时序分析。
set nf_upload_toggle_sync1_pins [get_pins -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_sync1_reg|stop_sync1_reg)/D}]
set_false_path -to $nf_upload_toggle_sync1_pins

set nf_upload_toggle_sync_cells [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_sync[12]_reg|stop_sync[12]_reg)}]
set_property ASYNC_REG TRUE $nf_upload_toggle_sync_cells

# 接收域描述符从 commit_toggle_rx 翻转前开始保持不变，直到下一次完整上传。
# 对 108 位描述符到音频域第一级采样寄存器施加绝对延迟和总线偏斜约束；
# sync1 到 sync2 仍按音频时钟正常分析。
set nf_upload_descriptor_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_bank_rx_reg|commit_length_rx_reg\[[0-9]+\]|commit_flags_rx_reg\[[0-9]+\]|commit_family_rx_reg|commit_mode_rx_reg\[[0-9]+\]|commit_repeat_rx_reg\[[0-9]+\]|commit_transaction_id_rx_reg\[[0-9]+\])}]
set nf_upload_descriptor_dst [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_bank_sync1_reg|commit_length_sync1_reg\[[0-9]+\]|commit_flags_sync1_reg\[[0-9]+\]|commit_family_sync1_reg|commit_mode_sync1_reg\[[0-9]+\]|commit_repeat_sync1_reg\[[0-9]+\]|commit_transaction_id_sync1_reg\[[0-9]+\])}]
set_max_delay 40.000 -datapath_only \
    -from $nf_upload_descriptor_src -to $nf_upload_descriptor_dst
set_bus_skew 40.000 \
    -from $nf_upload_descriptor_src -to $nf_upload_descriptor_dst

# ACK 字节通过异步 FIFO 跨域。分别约束两个方向的 9 位 Gray 指针：
# 从源寄存器到对侧时钟域第一级同步器。datapath-only 最大延迟去掉无意义的
# 异步时钟相位关系但仍限制物理布线，总线偏斜约束保护 Gray 码单比特变化假设。
set nf_ack_wr_gray_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/wr_gray_reg\[[0-9]+\]}]
set nf_ack_wr_gray_dst [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/wr_gray_r1_reg\[[0-9]+\]}]
set nf_ack_rd_gray_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/rd_gray_reg\[[0-9]+\]}]
set nf_ack_rd_gray_dst [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/rd_gray_w1_reg\[[0-9]+\]}]
set nf_ack_gray_sync_cells [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/(wr_gray_r[12]_reg\[[0-9]+\]|rd_gray_w[12]_reg\[[0-9]+\])}]
set_property ASYNC_REG TRUE $nf_ack_gray_sync_cells
set_max_delay 40.000 -datapath_only \
    -from $nf_ack_wr_gray_src -to $nf_ack_wr_gray_dst
set_bus_skew 40.000 \
    -from $nf_ack_wr_gray_src -to $nf_ack_wr_gray_dst
set_max_delay 40.000 -datapath_only \
    -from $nf_ack_rd_gray_src -to $nf_ack_rd_gray_dst
set_bus_skew 40.000 \
    -from $nf_ack_rd_gray_src -to $nf_ack_rd_gray_dst

set nf_capture_descriptor_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_capture/(done_frame_id_reg\[[0-9]+\]|done_start_sample_index_reg\[[0-9]+\]|done_mode_reg\[[0-9]+\]|done_family_reg|done_upload_source_reg|done_transaction_id_reg\[[0-9]+\])}]
set nf_capture_descriptor_dst [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_capture/(frame_id_reg\[[0-9]+\]|frame_start_sample_index_reg\[[0-9]+\]|frame_mode_reg\[[0-9]+\]|frame_family_48k_reg|frame_upload_source_reg|frame_transaction_id_reg\[[0-9]+\])}]
set_max_delay 80.000 -datapath_only \
    -from $nf_capture_descriptor_src -to $nf_capture_descriptor_dst
set_bus_skew 40.000 \
    -from $nf_capture_descriptor_src -to $nf_capture_descriptor_dst

# TX 数据、控制信号和转发 TXC 均由 IOB ODDR 输出。板上将 TXDLY
# 配置为低电平，因此 MMCM 使 TXC 相对 TXD 延迟约 2 ns。
set nf_rgmii_txc_oddr_c [get_pins u_dac24_udp_network/u_rgmii_tx/u_txc_oddr/C]
create_generated_clock -name rgmii_txc_100m \
    -source $nf_rgmii_txc_oddr_c -divide_by 1 [get_ports mac_txclk]
set_output_delay -clock rgmii_txc_100m -max 1.000 \
    [get_ports {mac_txctl mac_txd[*]}]
set_output_delay -clock rgmii_txc_100m -min -1.000 \
    [get_ports {mac_txctl mac_txd[*]}]

# 在 100 Mb/s 模式下，TXD/CTL 在完整的 40 ns 周期内保持同一个半字节，
# 并在 ODDR 的两个边沿重复输出。下降沿采用相同的保守采样窗口约束。
set_output_delay -clock rgmii_txc_100m -clock_fall -add_delay -max 1.000 \
    [get_ports {mac_txctl mac_txd[*]}]
set_output_delay -clock rgmii_txc_100m -clock_fall -add_delay -min -1.000 \
    [get_ports {mac_txctl mac_txd[*]}]


#=============================================================
# 6）人工输入 false path 约束
#
# key_kc[3:0] 来自矩阵按键，属于人工慢速输入。
#
# 这些信号不是高速同步数据输入，顶层会在 20MHz 时钟域内
# 进行同步和消抖，因此这里设置 false path。
#=============================================================
set_false_path -from [get_ports {key_kc[*]}]
set_false_path -to [get_ports {key_kr[*]}]


#=============================================================
# 7）控制域与音频域异步时钟组
#
# 两个音频时钟由独立 MMCM 产生，在 BUFGMUX_CTRL 后物理互斥。
# 模式控制使用两级同步器跨入当前音频域；采样率家族切换期间
# 数据通路保持异步复位，切换后同步释放。因此 20 MHz 控制域
# 与两个音频域之间均按异步时钟组处理。
#=============================================================

# 不使用覆盖整个 20 MHz/音频域的 set_clock_groups -asynchronous。
# 该粗粒度例外会吞掉 mode_shadow bundled-data 的 absolute max-delay。
# 这里只对已审计的第一拍同步器和 BUFGMUX_CTRL 选择脚做精确 false path；
# mode_shadow -> audio_mode 则保留为有界的异步 datapath-only 路径。
set nf_ctrl_to_audio_sync_pins [get_pins -hierarchical -regexp \
    {.*(family_audio_meta_reg|rst_request_sync_reg\[0\]|u_nf_mode_cdc_handshake/req_meta_reg)/D}]
set nf_audio_to_ctrl_sync_pins [get_pins -hierarchical -regexp \
    {.*u_nf_mode_cdc_handshake/ack_meta_reg/D}]
set nf_bufgmux_select_pins [get_pins -hierarchical -regexp \
    {.*u_bufgmux_audio_family/S[01]}]
set_false_path -to $nf_ctrl_to_audio_sync_pins
set_false_path -to $nf_audio_to_ctrl_sync_pins
set_false_path -to $nf_bufgmux_select_pins

set_clock_groups -logically_exclusive \
    -group [get_clocks [list $nf_clk_44k1 dac_clk_44k1_128x]] \
    -group [get_clocks [list $nf_clk_48k dac_clk_48k_128x]]

# mode_shadow[1:0] 是捆绑数据 CDC 总线。从发出请求到目标端返回同步
# 应答，源端始终保持两位数据稳定；目标端还会再等待三个音频时钟周期后
# 才进行原子采样。将物理偏斜限制为一个 20 MHz 源时钟周期，避免布局
# 布线把两位数据分离到足以破坏该协议假设。Vivado 2018.3 要求
# set_bus_skew 的端点是时序单元，而不是 Q/D 管脚。
set nf_mode_shadow_cells [get_cells -hierarchical -regexp \
    {.*u_nf_mode_cdc_handshake/mode_shadow_reg\[[01]\]}]
set nf_audio_mode_cells [get_cells -hierarchical -regexp \
    {.*u_nf_mode_cdc_handshake/audio_mode_reg\[[01]\]}]
set_bus_skew 50.000 -from $nf_mode_shadow_cells -to $nf_audio_mode_cells

# 仅限制相对偏斜无法约束两位数据整体的传输时间。源端会保持 mode_shadow
# 直到收到应答，目标端在采样前还等待三个音频时钟，因此一个 20 MHz
# 控制周期是保守的绝对数据路径上限，并留有充足协议余量。
set_max_delay 50.000 -datapath_only \
    -from $nf_mode_shadow_cells -to $nf_audio_mode_cells


#=============================================================
# 8) 已审计的 RGMII RX -> 内部网络时钟 Methodology 豁免
#
# rgmii_rxclk_100m 来自板上 PHY，clk_net_25m_unbuf 来自 FPGA MMCM，
# 两者物理上异步且本来就不应具有共同主时钟或共同树节点。相关跨域路径没有
# 使用全局 set_clock_groups -asynchronous，而是分别采用两级同步器、Gray FIFO
# 以及带 max-delay/bus-skew 的 bundled-data 握手；这样才能继续审计多位总线。
# 因此仅对这两个确定对象豁免 TIMING-6/TIMING-7，不豁免任何实际 CDC 路径。
#=============================================================
create_waiver -type METHODOLOGY -id {TIMING-6} -user {DAC24 project} \
    -desc {The external PHY RX clock and the internal 25 MHz network clock are asynchronous. Their CDC paths use audited synchronizers, Gray FIFOs, or bounded bundled-data constraints; a global asynchronous clock group would incorrectly override those path-specific checks.} \
    -objects [get_clocks rgmii_rxclk_100m] \
    -objects [get_clocks clk_net_25m_unbuf]

create_waiver -type METHODOLOGY -id {TIMING-7} -user {DAC24 project} \
    -desc {The external PHY RX clock and the internal 25 MHz network clock intentionally have no common clock-tree node. All crossings are handled and audited as asynchronous CDC paths.} \
    -objects [get_clocks rgmii_rxclk_100m] \
    -objects [get_clocks clk_net_25m_unbuf]
