set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
open_checkpoint [file join $project_dir network_capture results cdc_audit_2025_2 board_cdc_audit_synthesized.dcp]
foreach pattern [list \
    {.*u_upload_buffer/commit_.*_rx_reg.*} \
    {.*u_upload_buffer/commit_.*sync1_reg.*} \
    {.*u_capture/done_.*_reg.*} \
    {.*u_capture/frame_.*_reg.*} \
    {.*u_ack_async_fifo/.*gray.*reg.*}] {
    puts "CDC_NAME_PATTERN=$pattern"
    foreach c [lsort [get_cells -hierarchical -regexp $pattern]] {
        puts [get_property NAME $c]
    }
}
foreach c [lsort [get_cells -hierarchical -regexp \
    {.*u_(ack|arp)_async_fifo/.*(data|mem).*reg.*}]] {
    puts "FIFO_DATA_CELL=[get_property NAME $c] REF=[get_property REF_NAME $c]"
}
close_design
exit
