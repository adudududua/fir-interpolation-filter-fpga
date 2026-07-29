#=============================================================
# 文件名       : run_ila_image_rejection_sim.tcl
# 脚本名       : run_ila_image_rejection_sim
# 功能简述     : 运行 ILA 演示源、完整第一级 FIR 和固定频点检测
#                的端到端 XSim 自动化验证。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado Simulator
# 修订记录     :
#                2026-07-19：新增 ILA 演示端到端仿真脚本。
#=============================================================

set script_dir [file dirname [file normalize [info script]]]
set source_dir [file join $script_dir XC7A35T_interp.srcs sources_1 new]
set sim_dir [file join $script_dir XC7A35T_interp.srcs sim_1 new]

# 原工程的部分板级测试文件带同名轻量桩模块。这里使用独立工程，
# 只装入端到端演示所需的真实 RTL，避免桩模块参与自动编译排序。
create_project ila_demo_sim [file join $script_dir .ila_demo_sim_project] \
    -force -part xc7a35tfgg484-2

set include_file [file join $source_dir all2x_v3 all2x_v3_stage1_coeff_pkg.vh]
add_files -norecurse $include_file
set_property is_global_include true [get_files $include_file]
add_files -norecurse [list \
    [file join $source_dir ila_demo_multitone_source.v] \
    [file join $source_dir ila_image_rejection_monitor.v] \
    [file join $source_dir all2x_v6 round_sat_shift_compact.v] \
    [file join $source_dir all2x_v3 interp2_stage1_strict_halfband_bram_ce.v] \
    [file join $source_dir ila_demo_mix_4k1_15k_441.mem] \
    [file join $source_dir ila_demo_refs_15k_40k_441.mem] \
]
add_files -norecurse -fileset sim_1 \
    [file join $sim_dir tb_ila_image_rejection_demo.v]

set_property top tb_ila_image_rejection_demo [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
close_project
exit
