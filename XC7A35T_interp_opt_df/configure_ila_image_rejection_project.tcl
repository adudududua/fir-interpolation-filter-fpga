#=============================================================
# 文件名       : configure_ila_image_rejection_project.tcl
# 脚本名       : configure_ila_image_rejection_project
# 功能简述     : 向已打开工程加入 ILA 镜像演示 RTL/MEM/仿真文件，
#                并创建 4096 深度、26 探针的 ILA 6.x 调试核。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado
# 修订记录     :
#                2026-07-19：新增 ILA 演示工程配置脚本。
#                2026-07-19：增加 opt_design 前置钩子；在现有音频
#                            MMCM增加100MHz输出并专门驱动Debug Hub。
#                2026-07-19：ILA 扩展为23路探针，增加实际DAC码流、
#                            DAC模式/时钟与1x～128x采样更新脉冲。
#                2026-07-19：ILA扩展为26路探针，增加独立100MHz
#                            DAC_CLK测频结果、边沿计数和有效脉冲。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set source_dir [file join $script_dir XC7A35T_interp.srcs sources_1 new]
set sim_dir [file join $script_dir XC7A35T_interp.srcs sim_1 new]

proc add_design_file_if_needed {file_path} {
    if {[llength [get_files -quiet [file normalize $file_path]]] == 0} {
        add_files -norecurse -fileset sources_1 [file normalize $file_path]
    }
}

proc add_sim_file_if_needed {file_path} {
    if {[llength [get_files -quiet [file normalize $file_path]]] == 0} {
        add_files -norecurse -fileset sim_1 [file normalize $file_path]
    }
}

foreach file_name {
    dac_clock_frequency_meter.v
    ila_demo_multitone_source.v
    ila_image_rejection_monitor.v
    ila_demo_mix_4k1_15k_441.mem
    ila_demo_refs_15k_40k_441.mem
} {
    add_design_file_if_needed [file join $source_dir $file_name]
}

add_sim_file_if_needed [file join $sim_dir tb_ila_image_rejection_demo.v]
add_sim_file_if_needed [file join $sim_dir tb_dac_clock_frequency_meter.v]

set audio_clock_core [get_ips clk_wiz_audio_44k1]
set_property -dict [list \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT2_REQUESTED_PHASE {0.000} \
    CONFIG.CLKOUT2_REQUESTED_DUTY_CYCLE {50.000} \
    CONFIG.CLKOUT2_DRIVES {BUFG} \
] $audio_clock_core
generate_target all $audio_clock_core

if {[llength [get_ips -quiet ila_image_rejection]] == 0} {
    create_ip -name ila -vendor xilinx.com -library ip \
        -module_name ila_image_rejection \
        -dir [file join $script_dir XC7A35T_interp.srcs sources_1 ip]
}

set ila_core [get_ips ila_image_rejection]
set_property -dict [list \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_NUM_OF_PROBES {26} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {24} \
    CONFIG.C_PROBE2_WIDTH {24} \
    CONFIG.C_PROBE3_WIDTH {24} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {16} \
    CONFIG.C_PROBE6_WIDTH {16} \
    CONFIG.C_PROBE7_WIDTH {16} \
    CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_PROBE9_WIDTH {8} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {9} \
    CONFIG.C_PROBE12_WIDTH {8} \
    CONFIG.C_PROBE13_WIDTH {2} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {1} \
    CONFIG.C_PROBE22_WIDTH {1} \
    CONFIG.C_PROBE23_WIDTH {24} \
    CONFIG.C_PROBE24_WIDTH {20} \
    CONFIG.C_PROBE25_WIDTH {1} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_INPUT_PIPE_STAGES {0} \
] $ila_core

# Vivado 2018.3 在修改 ILA 探针数量后可能继续复用旧 stub/output product。
# 显式清除全部目标，保证顶层立即看到新的 probe11～probe22 端口。
reset_target all $ila_core
generate_target all $ila_core
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property top board_demo_competition_dac8_top [get_filesets sources_1]

set debug_hub_hook [file normalize \
    [file join $script_dir configure_ila_debug_hub_100m.tcl]]
set_property STEPS.OPT_DESIGN.TCL.PRE $debug_hub_hook [get_runs impl_1]
