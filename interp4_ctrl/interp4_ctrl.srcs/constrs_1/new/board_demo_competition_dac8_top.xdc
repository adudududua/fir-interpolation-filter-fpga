# =========================================================
# 姣旇禌 DAC demo 绾︽潫鏂囦欢
#
# 杩欎唤绾︽潫鍙湇鍔′簬褰撳墠鐨?姣旇禌 棰勯獙璇佺増鏈€?
# 鍚庨潰濡傛灉杩佺Щ鍒拌禌鏂规爣鍑嗘澘锛屼細鍐嶅崟鐙啓涓€浠芥柊鐨?.xdc銆?
# =========================================================

# ---------------------------------------------------------
# 1) 鏃堕挓绾︽潫
# 杩欓噷鍋囪浣犵殑鏉夸笂 clk 鏄?50MHz锛屾墍浠ユ椂閽熷懆鏈熸槸 20ns
# ---------------------------------------------------------
create_clock -period 20.000 -name sys_clk [get_ports clk]

# ---------------------------------------------------------
# 2) IO 鐢靛钩鏍囧噯
# 褰撳墠榛樿閮界敤 3.3V CMOS锛屼篃灏辨槸 LVCMOS33
# ---------------------------------------------------------
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports dac_clk]

set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data[7]}]

# set_property IOSTANDARD LVCMOS33 [get_ports {mode_led[0]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {mode_led[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports sw0]
set_property IOSTANDARD LVCMOS33 [get_ports sw1]
set_property IOSTANDARD LVCMOS33 [get_ports sw2]

# ---------------------------------------------------------
# 3) 鏉夸笂宸茬粡纭畾鐨勭鑴?
# ---------------------------------------------------------
set_property PACKAGE_PIN R4 [get_ports clk]
set_property PACKAGE_PIN AB20 [get_ports rst_n]
# set_property PACKAGE_PIN K14 [get_ports {mode_led[0]}]
# set_property PACKAGE_PIN L15 [get_ports {mode_led[1]}]
set_property PACKAGE_PIN W19 [get_ports sw0]
set_property PACKAGE_PIN AA21 [get_ports sw1]
set_property PACKAGE_PIN AA19 [get_ports sw2]

# ---------------------------------------------------------
# 4) 澶栨帴 DA9708 鐨?DAC 寮曡剼鏄犲皠
# ---------------------------------------------------------

set_property PACKAGE_PIN G16 [get_ports dac_clk]

set_property PACKAGE_PIN H19 [get_ports {dac_data[0]}]
set_property PACKAGE_PIN E19 [get_ports {dac_data[1]}]
set_property PACKAGE_PIN H18 [get_ports {dac_data[2]}]
set_property PACKAGE_PIN G18 [get_ports {dac_data[3]}]
set_property PACKAGE_PIN F18 [get_ports {dac_data[4]}]
set_property PACKAGE_PIN G17 [get_ports {dac_data[5]}]
set_property PACKAGE_PIN E17 [get_ports {dac_data[6]}]
set_property PACKAGE_PIN C17 [get_ports {dac_data[7]}]

# ---------------------------------------------------------
# 5) IO 杈规部閫熷害璁剧疆
#
# dac_clk 鏄?DA9708 鐨勯噰鏍锋椂閽熴€?
# 鍦?128x 妯″紡涓嬶紝dac_clk 浼氳揪鍒?5.6448MHz / 6.144MHz銆?
# 濡傛灉杈规部澶參锛岀ず娉㈠櫒涓婂彲鑳戒細鐪嬪埌绫讳技鍓婇《姝ｅ鸡鐨勫渾婊戞尝褰€?
#
# 鍥犳 dac_clk 鍗曠嫭浣跨敤 FAST 杈规部锛屽苟璁剧疆 8mA 椹卞姩鑳藉姏銆?
#
# dac_data[7:0] 浠嶄繚鎸?SLOW銆?
# 鍘熷洜鏄?8 鏍规暟鎹嚎鍚屾椂缈昏浆鏃讹紝鎱㈣竟娌垮彲浠ラ檷浣庢尟閾冦€佷覆鎵板拰姣涘埡銆?
# ---------------------------------------------------------
set_property SLEW FAST [get_ports dac_clk]
set_property DRIVE 8 [get_ports dac_clk]

set_property SLEW SLOW [get_ports {dac_data[0]}]
set_property SLEW SLOW [get_ports {dac_data[1]}]
set_property SLEW SLOW [get_ports {dac_data[2]}]
set_property SLEW SLOW [get_ports {dac_data[3]}]
set_property SLEW SLOW [get_ports {dac_data[4]}]
set_property SLEW SLOW [get_ports {dac_data[5]}]
set_property SLEW SLOW [get_ports {dac_data[6]}]
set_property SLEW SLOW [get_ports {dac_data[7]}]

# ---------------------------------------------------------
# 6) 44.1kHz / 48kHz 涓ゅ闊抽鏃堕挓浜掓枼绾︽潫
#
# 涓や釜 MMCM 鍚屾椂瀛樺湪锛屼絾缁忚繃 BUFGMUX 鍚庯紝
# 涓嬫父鎻掑€奸摼鍚屼竴鏃跺埢鍙細浣跨敤鍏朵腑涓€璺煶棰戞椂閽熴€?
#
# 杩欓噷涓嶈兘浣跨敤 if 鍒ゆ柇锛屽洜涓?Vivado 2018.3 鐨?XDC
# 瀵归儴鍒?Tcl 鎺у埗璇彞鏀寔涓嶅ソ銆?
# ---------------------------------------------------------
set_clock_groups -physically_exclusive -group [get_clocks -quiet -of_objects [get_pins u_clk_wiz_audio_44k1/inst/mmcm_adv_inst/CLKOUT0]] -group [get_clocks -quiet -of_objects [get_pins u_clk_wiz_audio_48k/inst/mmcm_adv_inst/CLKOUT0]]

# ---------------------------------------------------------
# 7) 鎷ㄧ爜寮€鍏冲拰澶栭儴澶嶄綅鏄汉宸ユ參閫熶俊鍙?
# ---------------------------------------------------------
set_false_path -from [get_ports {sw0 sw1 sw2 rst_n}]


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_audio_128x_sel]]
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe0]
set_property port_width 24 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {u_demo_interp_dac8_mmcm_common/dbg_y4_w[0]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[1]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[2]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[3]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[4]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[5]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[6]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[7]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[8]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[9]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[10]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[11]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[12]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[13]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[14]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[15]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[16]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[17]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[18]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[19]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[20]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[21]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[22]} {u_demo_interp_dac8_mmcm_common/dbg_y4_w[23]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe1]
set_property port_width 6 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_demo_interp_dac8_mmcm_common/rom_addr[0]} {u_demo_interp_dac8_mmcm_common/rom_addr[1]} {u_demo_interp_dac8_mmcm_common/rom_addr[2]} {u_demo_interp_dac8_mmcm_common/rom_addr[3]} {u_demo_interp_dac8_mmcm_common/rom_addr[4]} {u_demo_interp_dac8_mmcm_common/rom_addr[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe2]
set_property port_width 24 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_demo_interp_dac8_mmcm_common/dbg_y8_w[0]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[1]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[2]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[3]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[4]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[5]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[6]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[7]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[8]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[9]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[10]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[11]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[12]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[13]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[14]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[15]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[16]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[17]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[18]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[19]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[20]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[21]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[22]} {u_demo_interp_dac8_mmcm_common/dbg_y8_w[23]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe3]
set_property port_width 2 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_demo_interp_dac8_mmcm_common/mode_state[0]} {u_demo_interp_dac8_mmcm_common/mode_state[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe4]
set_property port_width 24 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_demo_interp_dac8_mmcm_common/selected_sample[0]} {u_demo_interp_dac8_mmcm_common/selected_sample[1]} {u_demo_interp_dac8_mmcm_common/selected_sample[2]} {u_demo_interp_dac8_mmcm_common/selected_sample[3]} {u_demo_interp_dac8_mmcm_common/selected_sample[4]} {u_demo_interp_dac8_mmcm_common/selected_sample[5]} {u_demo_interp_dac8_mmcm_common/selected_sample[6]} {u_demo_interp_dac8_mmcm_common/selected_sample[7]} {u_demo_interp_dac8_mmcm_common/selected_sample[8]} {u_demo_interp_dac8_mmcm_common/selected_sample[9]} {u_demo_interp_dac8_mmcm_common/selected_sample[10]} {u_demo_interp_dac8_mmcm_common/selected_sample[11]} {u_demo_interp_dac8_mmcm_common/selected_sample[12]} {u_demo_interp_dac8_mmcm_common/selected_sample[13]} {u_demo_interp_dac8_mmcm_common/selected_sample[14]} {u_demo_interp_dac8_mmcm_common/selected_sample[15]} {u_demo_interp_dac8_mmcm_common/selected_sample[16]} {u_demo_interp_dac8_mmcm_common/selected_sample[17]} {u_demo_interp_dac8_mmcm_common/selected_sample[18]} {u_demo_interp_dac8_mmcm_common/selected_sample[19]} {u_demo_interp_dac8_mmcm_common/selected_sample[20]} {u_demo_interp_dac8_mmcm_common/selected_sample[21]} {u_demo_interp_dac8_mmcm_common/selected_sample[22]} {u_demo_interp_dac8_mmcm_common/selected_sample[23]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe5]
set_property port_width 24 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_demo_interp_dac8_mmcm_common/x_in[0]} {u_demo_interp_dac8_mmcm_common/x_in[1]} {u_demo_interp_dac8_mmcm_common/x_in[2]} {u_demo_interp_dac8_mmcm_common/x_in[3]} {u_demo_interp_dac8_mmcm_common/x_in[4]} {u_demo_interp_dac8_mmcm_common/x_in[5]} {u_demo_interp_dac8_mmcm_common/x_in[6]} {u_demo_interp_dac8_mmcm_common/x_in[7]} {u_demo_interp_dac8_mmcm_common/x_in[8]} {u_demo_interp_dac8_mmcm_common/x_in[9]} {u_demo_interp_dac8_mmcm_common/x_in[10]} {u_demo_interp_dac8_mmcm_common/x_in[11]} {u_demo_interp_dac8_mmcm_common/x_in[12]} {u_demo_interp_dac8_mmcm_common/x_in[13]} {u_demo_interp_dac8_mmcm_common/x_in[14]} {u_demo_interp_dac8_mmcm_common/x_in[15]} {u_demo_interp_dac8_mmcm_common/x_in[16]} {u_demo_interp_dac8_mmcm_common/x_in[17]} {u_demo_interp_dac8_mmcm_common/x_in[18]} {u_demo_interp_dac8_mmcm_common/x_in[19]} {u_demo_interp_dac8_mmcm_common/x_in[20]} {u_demo_interp_dac8_mmcm_common/x_in[21]} {u_demo_interp_dac8_mmcm_common/x_in[22]} {u_demo_interp_dac8_mmcm_common/x_in[23]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe6]
set_property port_width 8 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_demo_interp_dac8_mmcm_common/dac_data_r[0]} {u_demo_interp_dac8_mmcm_common/dac_data_r[1]} {u_demo_interp_dac8_mmcm_common/dac_data_r[2]} {u_demo_interp_dac8_mmcm_common/dac_data_r[3]} {u_demo_interp_dac8_mmcm_common/dac_data_r[4]} {u_demo_interp_dac8_mmcm_common/dac_data_r[5]} {u_demo_interp_dac8_mmcm_common/dac_data_r[6]} {u_demo_interp_dac8_mmcm_common/dac_data_r[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe7]
set_property port_width 2 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_demo_interp_dac8_mmcm_common/ila_mode_sel_w[0]} {u_demo_interp_dac8_mmcm_common/ila_mode_sel_w[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe8]
set_property port_width 8 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_demo_interp_dac8_mmcm_common/sample_u8_w[0]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[1]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[2]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[3]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[4]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[5]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[6]} {u_demo_interp_dac8_mmcm_common/sample_u8_w[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list u_demo_interp_dac8_mmcm_common/dbg_y4_valid_w]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list u_demo_interp_dac8_mmcm_common/dbg_y8_valid_w]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list u_demo_interp_dac8_mmcm_common/selected_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list u_demo_interp_dac8_mmcm_common/x_in_update_ce]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list u_demo_interp_dac8_mmcm_common/x_in_valid]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_audio_128x_sel]
