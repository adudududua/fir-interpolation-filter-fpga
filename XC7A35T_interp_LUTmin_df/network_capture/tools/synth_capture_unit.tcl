# 执行快速单元综合，确认 4096x24 双时钟采集存储器映射为块 RAM，
# 再运行耗时更长的完整竞赛设计综合。
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. ..]]
set result_dir [file join $project_dir network_capture results synth_capture_unit]
file mkdir $result_dir
read_verilog [file join $project_dir network_capture rtl dac24_capture_pingpong.v]
synth_design -top dac24_capture_pingpong -part xc7a35tfgg484-2
report_utilization -hierarchical -file [file join $result_dir utilization.rpt]
write_checkpoint -force [file join $result_dir capture_sdp_synth.dcp]
puts "CAPTURE_UNIT_SYNTH_PASS"
