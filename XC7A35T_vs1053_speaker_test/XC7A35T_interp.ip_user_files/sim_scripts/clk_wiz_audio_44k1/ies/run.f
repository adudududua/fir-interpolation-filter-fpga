-makelib ies_lib/xil_defaultlib -sv \
  "E:/app/Xilinx2018.3/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
-endlib
-makelib ies_lib/xpm \
  "E:/app/Xilinx2018.3/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../XC7A35T_interp.srcs/sources_1/ip/clk_wiz_audio_44k1/clk_wiz_audio_44k1_clk_wiz.v" \
  "../../../../XC7A35T_interp.srcs/sources_1/ip/clk_wiz_audio_44k1/clk_wiz_audio_44k1.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

