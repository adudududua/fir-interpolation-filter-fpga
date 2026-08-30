# 独立综合 Phase 2 接收模块；用法：vivado -mode batch -source 本文件 -tclargs <top>。
set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir .. rtl]]
set top_name [lindex $argv 0]

if {$top_name eq "rgmii100_rx"} {
    read_verilog [file join $rtl_dir rgmii100_rx.v]
} elseif {$top_name eq "udp_ipv4_rx_parser"} {
    read_verilog [file join $rtl_dir ethernet_crc32.v]
    read_verilog [file join $rtl_dir udp_ipv4_rx_parser.v]
} elseif {$top_name eq "dac24_upload_protocol_rx"} {
    read_verilog [file join $rtl_dir ethernet_crc32.v]
    read_verilog [file join $rtl_dir dac24_upload_protocol_rx.v]
} else {
    error "未知 top：$top_name"
}

synth_design -top $top_name -part xc7a35tfgg484-2
create_clock -period 40.000 -name unit_clk [get_ports -quiet {clk rx_clk}]
report_utilization
report_timing_summary -check_timing_verbose
puts "PHASE2_RX_UNIT_SYNTH_PASS: $top_name"
