set script_dir [file dirname [file normalize [info script]]]
set tool_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $tool_dir results active_268lut_2dsp board_routed_268lut_2dsp.dcp]
set output_dir [file join $tool_dir results active_268lut_2dsp analysis]
file mkdir $output_dir

if {![file isfile $checkpoint]} {
    error "Missing 2-DSP routed checkpoint: $checkpoint"
}

open_checkpoint $checkpoint

set lut_stream [open [file join $output_dir lut_cells_routed.tsv] w]
puts $lut_stream "REF_NAME\tORIG_REF_NAME\tNAME"
foreach cell [lsort [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]] {
    puts $lut_stream "[get_property REF_NAME $cell]\t[get_property ORIG_REF_NAME $cell]\t$cell"
}
close $lut_stream

set carry_stream [open [file join $output_dir carry_cells_routed.tsv] w]
puts $carry_stream "REF_NAME\tORIG_REF_NAME\tNAME"
foreach cell [lsort [get_cells -hierarchical -filter {REF_NAME == CARRY4}]] {
    puts $carry_stream "[get_property REF_NAME $cell]\t[get_property ORIG_REF_NAME $cell]\t$cell"
}
close $carry_stream

set ff_stream [open [file join $output_dir ff_cells_routed.tsv] w]
puts $ff_stream "REF_NAME\tORIG_REF_NAME\tNAME"
foreach cell [lsort [get_cells -hierarchical -filter {REF_NAME =~ FD*}]] {
    puts $ff_stream "[get_property REF_NAME $cell]\t[get_property ORIG_REF_NAME $cell]\t$cell"
}
close $ff_stream

set dsp_stream [open [file join $output_dir dsp_cells_routed.tsv] w]
puts $dsp_stream "REF_NAME\tORIG_REF_NAME\tNAME"
foreach cell [lsort [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]] {
    puts $dsp_stream "[get_property REF_NAME $cell]\t[get_property ORIG_REF_NAME $cell]\t$cell"
}
close $dsp_stream

report_utilization -hierarchical -hierarchical_min_primitive_count 0 \
    -file [file join $output_dir utilization_hierarchical_full.rpt]
puts "ANALYZE_2DSP_LUT_COUNT=[llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]"
puts "ANALYZE_2DSP_CARRY4_COUNT=[llength [get_cells -hierarchical -filter {REF_NAME == CARRY4}]]"
puts "ANALYZE_2DSP_FF_COUNT=[llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]"
puts "ANALYZE_2DSP_ROUTED_CELLS_PASS"
close_design
exit
