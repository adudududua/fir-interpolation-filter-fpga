// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
// Date        : Thu May 28 20:01:22 2026
// Host        : LAPTOP-7MNOORO6 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/20260128learn/fpga_class/interp4_ctrl/interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_48k/clk_wiz_audio_48k_stub.v
// Design      : clk_wiz_audio_48k
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a35tfgg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module clk_wiz_audio_48k(clkfb_in, clk_out1, clkfb_out, reset, locked, 
  clk_in1)
/* synthesis syn_black_box black_box_pad_pin="clkfb_in,clk_out1,clkfb_out,reset,locked,clk_in1" */;
  input clkfb_in;
  output clk_out1;
  output clkfb_out;
  input reset;
  output locked;
  input clk_in1;
endmodule
