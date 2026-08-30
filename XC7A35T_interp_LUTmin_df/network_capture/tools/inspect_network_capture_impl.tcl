set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. ..]]
open_checkpoint [file join $project_dir network_capture results implementation board_network_routed.dcp]
foreach cell [get_cells -hierarchical -filter {REF_NAME == RAMB36E1 && NAME =~ *u_capture_ram*}] {
    puts "CAPTURE_RAM=$cell"
    foreach pin_name {RSTREGB REGCEB ENBWREN} {
        set pin [get_pins -quiet $cell/$pin_name]
        puts "  $pin_name net=[get_nets -quiet -of_objects $pin]"
    }
    foreach property_name {DOA_REG DOB_REG READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B} {
        puts "  $property_name=[get_property $property_name $cell]"
    }
}
puts "CAPTURE_RESET_PINS=[llength [get_pins -hierarchical -regexp {.*u_dac24_udp_network/capture_rst_sync_reg\[[01]\]/CLR}]]"
puts "NETWORK_RESET_PINS=[llength [get_pins -hierarchical -regexp {.*net_rst_sync_reg\[[01]\]/CLR}]]"
puts "TXC_RESET_PINS=[llength [get_pins -hierarchical -regexp {.*u_dac24_udp_network/u_rgmii_tx/txc_rst_sync_reg\[[01]\]/CLR}]]"
