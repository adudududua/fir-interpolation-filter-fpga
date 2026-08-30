# Phase 2 最终布局布线签收审计。
# 用法：vivado -mode batch -source network_capture/tools/audit_release_2025_2.tcl

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set result_dir  [file join $project_dir network_capture results implementation]
set routed_dcp  [file join $result_dir board_network_routed.dcp]

proc require_count {label collection expected} {
    set actual [llength $collection]
    puts "RELEASE_AUDIT_${label}_COUNT=$actual"
    if {$actual != $expected} {
        error "$label matched $actual objects, expected $expected"
    }
}

proc require_true {label condition} {
    if {!$condition} {
        error "Release audit failed: $label"
    }
    puts "RELEASE_AUDIT_${label}=PASS"
}

open_checkpoint $routed_dcp

set rx_cells [get_cells -hierarchical -regexp \
    {.*u_dac24_udp_network/u_rgmii_rx/(rxd_fall_reg\[[0-3]\]|ctl_fall_reg)}]
require_count RGMII_RX_FALL_REG $rx_cells 5

set placed_in_iob 0
foreach rx_cell $rx_cells {
    set site [get_sites -quiet -of_objects $rx_cell]
    set bel  [get_bels -quiet -of_objects $rx_cell]
    puts "RELEASE_AUDIT_RX_CELL=[get_property NAME $rx_cell] SITE=$site BEL=$bel"
    if {[llength $site] == 1 && [regexp {ILOGIC} $bel]} {
        incr placed_in_iob
    }
}
require_true RGMII_RX_PLACED_IN_IOB [expr {$placed_in_iob == 5}]

set setup_bad [get_timing_paths -quiet -delay_type max -slack_lesser_than 0]
set hold_bad  [get_timing_paths -quiet -delay_type min -slack_lesser_than 0]
require_count NEGATIVE_SETUP_PATH $setup_bad 0
require_count NEGATIVE_HOLD_PATH $hold_bad 0

set rx_ports [get_ports {mac_rxctl mac_rxd[*]}]
set rx_d_pins [get_pins -of_objects $rx_cells -filter {REF_PIN_NAME == D}]
set rx_setup [get_timing_paths -quiet -delay_type max -from $rx_ports \
    -fall_to [get_clocks rgmii_rxclk_100m] -to $rx_d_pins -max_paths 5 -nworst 1]
set rx_hold [get_timing_paths -quiet -delay_type min -from $rx_ports \
    -fall_to [get_clocks rgmii_rxclk_100m] -to $rx_d_pins -max_paths 5 -nworst 1]
require_count RGMII_RX_SETUP_PATH $rx_setup 5
require_count RGMII_RX_HOLD_PATH $rx_hold 5
report_timing -delay_type max -from $rx_ports -fall_to [get_clocks rgmii_rxclk_100m] \
    -to $rx_d_pins -max_paths 5 -nworst 1 \
    -file [file join $result_dir rgmii_rx_fall_setup_routed.rpt]
report_timing -delay_type min -from $rx_ports -fall_to [get_clocks rgmii_rxclk_100m] \
    -to $rx_d_pins -max_paths 5 -nworst 1 \
    -file [file join $result_dir rgmii_rx_fall_hold_routed.rpt]

puts "RELEASE_AUDIT_2025_2_PASS"
close_design
exit
