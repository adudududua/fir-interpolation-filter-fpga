#=============================================================
# 文件名       : configure_ila_debug_hub_100m.tcl
# 脚本名       : configure_ila_debug_hub_100m
# 功能简述     : 在 opt_design 前把 Debug Hub 显式连接到现有音频
#                MMCM新增的自由运行100MHz调试/测频时钟，并写入正确
#                的100MHz频率参数。ILA采样时钟仍为5.6448MHz。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-19：新增固定100MHz Debug Hub配置。
#=============================================================

set debug_hub_name dbg_hub
set debug_hub_clock_hz 100000000
set debug_hub_clock_net [get_nets -quiet clk_debug_100m]

if {[llength $debug_hub_clock_net] != 1} {
    error "Expected exactly one clk_debug_100m net for Debug Hub, got: $debug_hub_clock_net"
}

set debug_hub [get_debug_cores -quiet $debug_hub_name]
if {[llength $debug_hub] != 1} {
    error "Debug Hub was not created during implementation link: $debug_hub"
}

set_property C_CLK_INPUT_FREQ_HZ $debug_hub_clock_hz $debug_hub
set_property C_ENABLE_CLK_DIVIDER false $debug_hub
set_property C_USER_SCAN_CHAIN 1 $debug_hub
connect_debug_port $debug_hub_name/clk $debug_hub_clock_net

puts "ILA_DEBUG_HUB_CONFIGURED core=$debug_hub_name clock_net=$debug_hub_clock_net frequency_hz=$debug_hub_clock_hz"
