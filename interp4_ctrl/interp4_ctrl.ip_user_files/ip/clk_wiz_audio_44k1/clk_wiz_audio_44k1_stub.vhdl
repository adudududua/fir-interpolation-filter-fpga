-- Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
-- Date        : Thu May 28 19:59:22 2026
-- Host        : LAPTOP-7MNOORO6 running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/20260128learn/fpga_class/interp4_ctrl/interp4_ctrl.srcs/sources_1/ip/clk_wiz_audio_44k1/clk_wiz_audio_44k1_stub.vhdl
-- Design      : clk_wiz_audio_44k1
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a35tfgg484-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity clk_wiz_audio_44k1 is
  Port ( 
    clkfb_in : in STD_LOGIC;
    clk_out1 : out STD_LOGIC;
    clkfb_out : out STD_LOGIC;
    reset : in STD_LOGIC;
    locked : out STD_LOGIC;
    clk_in1 : in STD_LOGIC
  );

end clk_wiz_audio_44k1;

architecture stub of clk_wiz_audio_44k1 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clkfb_in,clk_out1,clkfb_out,reset,locked,clk_in1";
begin
end;
