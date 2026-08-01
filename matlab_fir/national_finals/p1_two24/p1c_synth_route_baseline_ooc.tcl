set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_root [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set nf_root [file join $src_root national_finals]
set result_dir [file join $script_dir results p1c_baseline_ooc]
file mkdir $result_dir

set source_files [list \
    [file join $src_root all2x_v6 round_sat_shift_compact.v] \
    [file join $nf_root cic_interp16_n3_hold2_dsp_ce.v]]
foreach source_file $source_files {
    if {![file exists $source_file]} {
        error "Missing P1-C baseline source: $source_file"
    }
    read_verilog $source_file
}

synth_design -top cic_interp16_n3_hold2_dsp_ce \
    -part xc7a35tfgg484-2 -mode out_of_context \
    -flatten_hierarchy rebuilt -directive AreaOptimized_high \
    -generic INTEGRATOR_DSP_MODE=2
create_clock -name clk_audio_128x -period 162.760 [get_ports clk]

report_utilization -file [file join $result_dir utilization_synthesized.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical_synthesized.rpt]

set dsp_cells [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]
if {[llength $dsp_cells] != 2} {
    error "P1-C baseline expected exactly two DSP48E1 cells, got [llength $dsp_cells]"
}
set dsp_prop_file [file join $result_dir dsp48_properties_synthesized.rpt]
file delete -force $dsp_prop_file
foreach dsp_cell $dsp_cells {
    report_property -all $dsp_cell -append -file $dsp_prop_file
}

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
set dsp_prop_file [file join $result_dir dsp48_properties_routed.rpt]
file delete -force $dsp_prop_file
foreach dsp_cell $dsp_cells {
    report_property -all $dsp_cell -append -file $dsp_prop_file
}
write_checkpoint -force [file join $result_dir p1c_baseline_routed.dcp]

set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
puts "P1C_BASELINE_OOC_PASS"
puts "DSP_COUNT=[llength $dsp_cells]"
puts [format "WNS_NS=%.3f" [get_property SLACK $setup_path]]
puts [format "WHS_NS=%.3f" [get_property SLACK $hold_path]]
puts "RESULT_DIR=$result_dir"
