# Vivado 2025.2 新增网络功能 CDC 约束审计。
# 用法：
#   vivado -mode batch -source network_capture/tools/audit_cdc_constraints_2025_2.tcl

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set project_xpr [file join $project_dir XC7A35T_interp.xpr]
set result_dir  [file join $project_dir network_capture results cdc_audit_2025_2]
file mkdir $result_dir
set synthesized_dcp [file join $result_dir board_cdc_audit_synthesized.dcp]
set signature_file [file join $result_dir source_signature.txt]

proc require_count {label collection expected} {
    set actual [llength $collection]
    puts "CDC_AUDIT_${label}_COUNT=$actual"
    if {$actual != $expected} {
        error "$label matched $actual objects, expected $expected"
    }
}

proc require_true {label condition} {
    if {!$condition} {
        error "CDC audit failed: $label"
    }
    puts "CDC_AUDIT_${label}=PASS"
}

open_project $project_xpr
set top_name [get_property TOP [get_filesets sources_1]]
set part_name [get_property PART [current_project]]
require_true TOP [expr {$top_name eq "board_demo_competition_dac8_top"}]
set source_signature ""
foreach source_file [lsort [concat \
        [get_files -quiet -of_objects [get_filesets sources_1]] \
        [get_files -quiet -of_objects [get_filesets constrs_1]]]] {
    if {[file exists $source_file]} {
        append source_signature "[file normalize $source_file]|[file mtime $source_file]|[file size $source_file]\n"
    }
}
set reuse_checkpoint 0
if {[file exists $synthesized_dcp] && [file exists $signature_file]} {
    set sig_handle [open $signature_file r]
    set old_signature [read $sig_handle]
    close $sig_handle
    set reuse_checkpoint [expr {$old_signature eq $source_signature}]
}

set required_rtl [list \
    rgmii100_rx.v udp_ipv4_rx_parser.v dac24_upload_protocol_rx.v \
    dac24_wave_upload_buffer.v udp_control_ack_tx.v \
    ethernet_frame_arbiter2.v ethernet_frame_arbiter3.v ack_async_fifo.v \
    arp_request_rx.v arp_reply_tx.v]
foreach leaf $required_rtl {
    set matches [get_files -quiet -of_objects [get_filesets sources_1] *$leaf]
    require_true "SOURCE_[string map {. _} $leaf]" [expr {[llength $matches] == 1}]
}

update_compile_order -fileset sources_1
if {$reuse_checkpoint} {
    close_project
    open_checkpoint $synthesized_dcp
} else {
    synth_design -top $top_name -part $part_name \
        -flatten_hierarchy none -directive RuntimeOptimized
    write_checkpoint -force $synthesized_dcp
    set sig_handle [open $signature_file w]
    puts -nonewline $sig_handle $source_signature
    close $sig_handle
}

# RGMII RX 使用 5 个无复位的下降沿 IOB 输入寄存器。逐一确认这些寄存器及其
# IOB 属性，并确认 5 条 falling-capture 建立/保持路径都存在且没有被 false path。
set rgmii_rx_clock [get_clocks rgmii_rxclk_100m]
set rgmii_rx_ports [get_ports {mac_rxctl mac_rxd[*]}]
set rgmii_rx_iob_cells [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_rgmii_rx/(rxd_fall_reg\[[0-3]\]|ctl_fall_reg)}]
set rgmii_rx_iob_d_pins [get_pins -of_objects $rgmii_rx_iob_cells -filter {REF_PIN_NAME == D}]
require_count RGMII_RX_CLOCK $rgmii_rx_clock 1
require_count RGMII_RX_INPUT_PORT $rgmii_rx_ports 5
require_count RGMII_RX_IOB_CELL $rgmii_rx_iob_cells 5
require_count RGMII_RX_IOB_DATA_PIN $rgmii_rx_iob_d_pins 5
set rgmii_rx_iob_true_count 0
foreach rx_cell $rgmii_rx_iob_cells {
    if {[get_property IOB $rx_cell] eq "TRUE"} {
        incr rgmii_rx_iob_true_count
    }
}
require_true RGMII_RX_IOB_ATTRIBUTE [expr {$rgmii_rx_iob_true_count == 5}]

set rgmii_fall_setup [get_timing_paths -quiet -delay_type max \
    -from $rgmii_rx_ports -fall_to $rgmii_rx_clock -to $rgmii_rx_iob_d_pins \
    -max_paths 20 -nworst 1]
set rgmii_fall_hold [get_timing_paths -quiet -delay_type min \
    -from $rgmii_rx_ports -fall_to $rgmii_rx_clock -to $rgmii_rx_iob_d_pins \
    -max_paths 20 -nworst 1]
require_count RGMII_RX_FALL_SETUP_PATH $rgmii_fall_setup 5
require_count RGMII_RX_FALL_HOLD_PATH $rgmii_fall_hold 5
report_timing -delay_type max -from $rgmii_rx_ports -fall_to $rgmii_rx_clock \
    -to $rgmii_rx_iob_d_pins -max_paths 5 -nworst 1 \
    -file [file join $result_dir rgmii_fall_setup_synthesized.rpt]
report_timing -delay_type min -from $rgmii_rx_ports -fall_to $rgmii_rx_clock \
    -to $rgmii_rx_iob_d_pins -max_paths 5 -nworst 1 \
    -file [file join $result_dir rgmii_fall_hold_synthesized.rpt]

set upload_toggle_first [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_sync1_reg|stop_sync1_reg)}]
set upload_toggle_all [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_sync[12]_reg|stop_sync[12]_reg)}]
require_count UPLOAD_TOGGLE_FIRST $upload_toggle_first 2
require_count UPLOAD_TOGGLE_ALL $upload_toggle_all 4

set upload_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_bank_rx_reg|commit_length_rx_reg\[[0-9]+\]|commit_flags_rx_reg\[[0-9]+\]|commit_family_rx_reg|commit_mode_rx_reg\[[0-9]+\]|commit_repeat_rx_reg\[[0-9]+\]|commit_transaction_id_rx_reg\[[0-9]+\])}]
set upload_dst [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_upload_buffer/(commit_bank_sync1_reg|commit_length_sync1_reg\[[0-9]+\]|commit_flags_sync1_reg\[[0-9]+\]|commit_family_sync1_reg|commit_mode_sync1_reg\[[0-9]+\]|commit_repeat_sync1_reg\[[0-9]+\]|commit_transaction_id_sync1_reg\[[0-9]+\])}]
# 输出倍率现在始终由实体 SW1～SW8 控制，playback_mode 只保留为
# RTL 接口兼容字段，在整机中没有功能消费者。Vivado 因此会成对删除
# commit_mode_rx[1:0] 和 commit_mode_sync1[1:0]；其余 101 位稳定描述符
# 仍全部存在并受 max-delay/bus-skew 约束。这里同时对源和目标计数，
# 防止只丢失单侧寄存器却被误判为合法优化。
require_count UPLOAD_DESCRIPTOR_SOURCE $upload_src 101
require_count UPLOAD_DESCRIPTOR_DESTINATION $upload_dst 101

set ack_wr_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/wr_gray_reg\[[0-9]+\]}]
set ack_wr_dst1 [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/wr_gray_r1_reg\[[0-9]+\]}]
set ack_wr_dst2 [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/wr_gray_r2_reg\[[0-9]+\]}]
set ack_rd_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/rd_gray_reg\[[0-9]+\]}]
set ack_rd_dst1 [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/rd_gray_w1_reg\[[0-9]+\]}]
set ack_rd_dst2 [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/rd_gray_w2_reg\[[0-9]+\]}]
# 当前 ACK FIFO 的写 Gray 最高位在满检测中未被使用，综合后源侧为 8 位，
# 但对侧两个同步级仍完整保留 9 位；读 Gray 两侧均为 9 位。
# ARP FIFO 使用同一个模块时，再按每个新增实例分别增加 8/9/9 与 9/9/9。
set fifo_instance_count [llength [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo}]]
require_count ACK_ARP_FIFO_INSTANCE \
    [get_cells -hierarchical -regexp {.*u_dac24_udp_network/u_(ack|arp)_async_fifo}] 2
require_count ACK_ARP_WR_GRAY_SOURCE $ack_wr_src [expr {8 * $fifo_instance_count}]
require_count ACK_ARP_WR_GRAY_STAGE1 $ack_wr_dst1 [expr {9 * $fifo_instance_count}]
require_count ACK_ARP_WR_GRAY_STAGE2 $ack_wr_dst2 [expr {9 * $fifo_instance_count}]
require_count ACK_ARP_RD_GRAY_SOURCE $ack_rd_src [expr {9 * $fifo_instance_count}]
require_count ACK_ARP_RD_GRAY_STAGE1 $ack_rd_dst1 [expr {9 * $fifo_instance_count}]
require_count ACK_ARP_RD_GRAY_STAGE2 $ack_rd_dst2 [expr {9 * $fifo_instance_count}]

# 9 位 rd_data_reg 已被 Vivado 合并为每个 FIFO 的 RAMB18E1 同步读输出寄存器。
# 对每个实例审计 RAM primitive 唯一存在，并检查其 CLKB 时钟确为 net25。
set fifo_read_data_regs [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_(ack|arp)_async_fifo/mem_reg}]
require_count ACK_ARP_REGISTERED_READ_BRAM $fifo_read_data_regs $fifo_instance_count
set net25_clock [get_clocks clk_net_25m_unbuf]
require_true NETWORK_25M_CLOCK_NONEMPTY [expr {[llength $net25_clock] == 1}]
foreach fifo_read_reg $fifo_read_data_regs {
    require_true "READ_DATA_IS_RAMB18_[string map {/ _} [get_property NAME $fifo_read_reg]]" \
        [expr {[get_property REF_NAME $fifo_read_reg] eq "RAMB18E1"}]
    set clock_pin [get_pins -of_objects $fifo_read_reg -filter {REF_PIN_NAME == CLKBWRCLK}]
    set pin_clocks [get_clocks -quiet -of_objects $clock_pin]
    require_true "READ_DATA_CLOCK_[string map {/ _ \[ _ \] _} [get_property NAME $fifo_read_reg]]" \
        [expr {[lsearch -exact $pin_clocks $net25_clock] >= 0}]
}

set capture_src [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_capture/(done_frame_id_reg\[[0-9]+\]|done_start_sample_index_reg\[[0-9]+\]|done_mode_reg\[[0-9]+\]|done_family_reg|done_upload_source_reg|done_transaction_id_reg\[[0-9]+\])}]
set capture_dst [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_capture/(frame_id_reg\[[0-9]+\]|frame_start_sample_index_reg\[[0-9]+\]|frame_mode_reg\[[0-9]+\]|frame_family_48k_reg|frame_upload_source_reg|frame_transaction_id_reg\[[0-9]+\])}]
require_count CAPTURE_DESCRIPTOR_SOURCE $capture_src 100
require_count CAPTURE_DESCRIPTOR_DESTINATION $capture_dst 100

foreach cell [concat $upload_toggle_all $ack_wr_dst1 $ack_wr_dst2 \
                       $ack_rd_dst1 $ack_rd_dst2] {
    set async_value [string toupper [get_property ASYNC_REG $cell]]
    require_true "ASYNC_REG_[string map {/ _ \[ _ \] _} [get_property NAME $cell]]" \
        [expr {$async_value eq "TRUE" || $async_value eq "1"}]
}

report_exceptions -summary \
    -file [file join $result_dir exceptions_summary.rpt]
report_cdc -details \
    -file [file join $result_dir cdc_synthesized.rpt]
check_timing -verbose \
    -file [file join $result_dir check_timing_synthesized.rpt]
write_checkpoint -force $synthesized_dcp

puts "CDC_AUDIT_2025_2_PASS"
close_design
catch {close_project}
exit
