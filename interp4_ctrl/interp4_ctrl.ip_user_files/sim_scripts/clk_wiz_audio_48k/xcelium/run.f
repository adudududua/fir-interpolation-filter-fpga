-makelib xcelium_lib/xil_defaultlib -sv \
  "D:/Tools/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
-endlib
-makelib xcelium_lib/xpm \
  "D:/Tools/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  "../../../../interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k_clk_wiz.v" \
  "../../../../interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k.v" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  glbl.v
-endlib

