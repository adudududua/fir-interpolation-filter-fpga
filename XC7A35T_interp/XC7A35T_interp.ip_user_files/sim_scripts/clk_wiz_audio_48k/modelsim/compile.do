vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/xpm

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap xpm modelsim_lib/msim/xpm

vlog -work xil_defaultlib -64 -incr -sv "+incdir+../../../ipstatic" \
"E:/app/Xilinx2018.3/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -64 -93 \
"E:/app/Xilinx2018.3/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib -64 -incr "+incdir+../../../ipstatic" \
"../../../../XC7A35T_interp.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k_clk_wiz.v" \
"../../../../XC7A35T_interp.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k.v" \

vlog -work xil_defaultlib \
"glbl.v"

