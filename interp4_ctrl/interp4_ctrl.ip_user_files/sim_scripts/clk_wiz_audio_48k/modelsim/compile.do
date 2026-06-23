vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/xpm

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap xpm modelsim_lib/msim/xpm

vlog -work xil_defaultlib -64 -incr -sv "+incdir+../../../ipstatic" \
"D:/Tools/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -64 -93 \
"D:/Tools/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib -64 -incr "+incdir+../../../ipstatic" \
"../../../../interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k_clk_wiz.v" \
"../../../../interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k.v" \

vlog -work xil_defaultlib \
"glbl.v"

