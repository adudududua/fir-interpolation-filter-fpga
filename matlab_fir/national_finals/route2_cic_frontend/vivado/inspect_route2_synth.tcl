set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. .. ..]]
set dcp [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.runs synth_1 board_demo_competition_dac8_top.dcp]
set result_dir [file normalize [file join $script_dir .. results]]
file mkdir $result_dir

open_checkpoint $dcp
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $result_dir route2_synth_hierarchical.rpt]

set handle [open [file join $result_dir route2_synth_dsp_cells.txt] w]
set cells [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]
puts $handle "DSP_COUNT=[llength $cells]"
foreach cell $cells {
    puts $handle "$cell | [get_property REF_NAME $cell]"
}
close $handle
close_design
puts "ROUTE2_SYNTH_INSPECTION_PASS"
