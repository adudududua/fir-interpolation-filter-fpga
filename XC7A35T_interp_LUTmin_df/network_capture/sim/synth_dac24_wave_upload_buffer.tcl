# 独立检查上传缓冲模块能否综合，并确认双 bank 被推断为 BRAM。
set script_dir [file dirname [file normalize [info script]]]
read_verilog [file join $script_dir .. rtl dac24_wave_upload_buffer.v]
synth_design -top dac24_wave_upload_buffer -part xc7a35tcsg324-2
create_clock -period 40.000 -name rx_clk [get_ports rx_clk]
create_clock -period 160.000 -name audio_clk [get_ports audio_clk]
set_clock_groups -asynchronous -group [get_clocks rx_clk] -group [get_clocks audio_clk]
report_utilization -file [file join $script_dir upload_buffer_utilization.rpt]
report_timing_summary -file [file join $script_dir upload_buffer_timing.rpt]
