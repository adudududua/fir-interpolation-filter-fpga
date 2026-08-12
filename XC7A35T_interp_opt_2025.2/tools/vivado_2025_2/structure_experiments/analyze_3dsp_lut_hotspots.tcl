set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file join $script_dir results \
    cic_dsp_mode1_20260811_232637 board_routed.dcp]
set output_file [file join $script_dir results \
    cic_dsp_mode1_20260811_232637 lut_cells_routed.tsv]

if {![file isfile $checkpoint]} {
    error "Missing baseline checkpoint: $checkpoint"
}

open_checkpoint $checkpoint
set stream [open $output_file w]
puts $stream "REF_NAME\tNAME"
foreach cell [lsort [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]] {
    puts $stream "[get_property REF_NAME $cell]\t$cell"
}
close $stream
puts "LUT_CELL_COUNT=[llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]"
puts "LUT_CELL_FILE=$output_file"
close_design
exit
