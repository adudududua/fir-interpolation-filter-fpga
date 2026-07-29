set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set run_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.runs impl_1]
set result_dir [file normalize [file join $script_dir .. vivado_results \
    board_dual_rate_areaopt]]
file mkdir $result_dir

open_checkpoint [file join $run_dir \
    board_demo_competition_dac8_top_placed.dcp]
report_clocks -file [file join $result_dir placed_clock_report_debug.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $result_dir placed_clock_interaction_debug.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir placed_timing_debug.rpt]
close_design
