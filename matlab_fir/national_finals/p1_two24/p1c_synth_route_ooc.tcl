set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_root [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set nf_root [file join $src_root national_finals]
set result_dir [file join $script_dir results p1c_ooc]
file mkdir $result_dir

set source_files [list \
    [file join $src_root all2x_v6 round_sat_shift_compact.v] \
    [file join $nf_root p1_two24 nf_cic_two24_integrator_pair_p1s.v] \
    [file join $nf_root p1_two24 cic_interp16_n3_hold2_two24_p1s_ce.v]]
foreach source_file $source_files {
    if {![file exists $source_file]} {
        error "Missing P1-C source: $source_file"
    }
    read_verilog $source_file
}

synth_design -top cic_interp16_n3_hold2_two24_p1s_ce \
    -part xc7a35tfgg484-2 -mode out_of_context \
    -flatten_hierarchy rebuilt -directive AreaOptimized_high
create_clock -name clk_audio_128x -period 162.760 [get_ports clk]

report_utilization -file [file join $result_dir utilization_synthesized.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical_synthesized.rpt]

set dsp_cells [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]
if {[llength $dsp_cells] != 1} {
    error "P1-C expected exactly one DSP48E1, got [llength $dsp_cells]"
}
report_property -all $dsp_cells \
    -file [file join $result_dir dsp48_properties_synthesized.rpt]

opt_design -directive Default
place_design
route_design
set route_status_text [report_route_status -return_string]
set route_handle [open [file join $result_dir route_status_routed.rpt] w]
puts $route_handle $route_status_text
close $route_handle
report_utilization -file [file join $result_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
report_power -file [file join $result_dir power_vectorless_routed.rpt]
report_property -all $dsp_cells \
    -file [file join $result_dir dsp48_properties_routed.rpt]
write_checkpoint -force [file join $result_dir p1c_two24_routed.dcp]

set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
puts "P1C_TWO24_OOC_PASS"
puts "DSP_COUNT=[llength $dsp_cells]"
puts [format "WNS_NS=%.3f" [get_property SLACK $setup_path]]
puts [format "WHS_NS=%.3f" [get_property SLACK $hold_path]]
puts "RESULT_DIR=$result_dir"
