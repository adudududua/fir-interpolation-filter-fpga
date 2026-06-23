vlib work
vlib riviera

vlib riviera/xil_defaultlib
vlib riviera/xpm

vmap xil_defaultlib riviera/xil_defaultlib
vmap xpm riviera/xpm

vlog -work xil_defaultlib  -sv2k12 "+incdir+../../../ipstatic" \
"D:/Tools/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -93 \
"D:/Tools/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../ipstatic" \
"../../../../interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k_clk_wiz.v" \
"../../../../interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k.v" \

vlog -work xil_defaultlib \
"glbl.v"

