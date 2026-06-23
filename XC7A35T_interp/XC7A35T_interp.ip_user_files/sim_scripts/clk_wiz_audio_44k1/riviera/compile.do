vlib work
vlib riviera

vlib riviera/xil_defaultlib
vlib riviera/xpm

vmap xil_defaultlib riviera/xil_defaultlib
vmap xpm riviera/xpm

vlog -work xil_defaultlib  -sv2k12 "+incdir+../../../ipstatic" \
"E:/app/Xilinx2018.3/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -93 \
"E:/app/Xilinx2018.3/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../ipstatic" \
"../../../../XC7A35T_interp.srcs/sources_1/ip/clk_wiz_audio_44k1/clk_wiz_audio_44k1_clk_wiz.v" \
"../../../../XC7A35T_interp.srcs/sources_1/ip/clk_wiz_audio_44k1/clk_wiz_audio_44k1.v" \

vlog -work xil_defaultlib \
"glbl.v"

