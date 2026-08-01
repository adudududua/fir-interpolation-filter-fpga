set script_dir [file dirname [file normalize [info script]]]
set nf_dir [file dirname $script_dir]
set repo_root [file normalize [file join $nf_dir .. ..]]
set src_root [file join $repo_root XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.srcs sources_1 new]
set nf_src [file join $src_root national_finals]
set out_dir [file join $nf_dir _work x3_20m vivado_core]
file mkdir $out_dir

read_verilog [file join $src_root all2x_v6 round_sat_shift_compact.v]
read_verilog [file join $src_root all2x_v6 bridge_valid_quantized_to_interp2_ce.v]
read_verilog [file join $nf_src nf_unified_fir_coeff_bram.v]
read_verilog [file join $nf_src nf_interp_fir3_shared_mac_ce.v]
read_verilog [file join $nf_src nf_async_fifo_gray.v]
read_verilog [file join $nf_src nf_x3_20m_fir_front.v]
read_verilog [file join $nf_src cic3_compensator_shiftadd_ce.v]
read_verilog [file join $nf_src cic_interp16_n3_hold2_dsp_ce.v]
read_verilog [file join $nf_src nf_x3_20m_filter_core.v]

synth_design -top nf_x3_20m_filter_core -part xc7a35tfgg484-2 \
    -flatten_hierarchy rebuilt -directive AreaOptimized_high

create_clock -name sys_clk_20m -period 50.000 [get_ports sys_clk]
create_clock -name audio_clk_6144k -period 162.760 [get_ports audio_clk]
set_clock_groups -asynchronous -group [get_clocks sys_clk_20m] \
    -group [get_clocks audio_clk_6144k]

opt_design -directive ExploreArea
report_utilization -file [file join $out_dir utilization_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 5 \
    -file [file join $out_dir utilization_hier_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $out_dir timing_synth.rpt]
report_cdc -details -file [file join $out_dir cdc_synth.rpt]
write_checkpoint -force [file join $out_dir x3_20m_core_synth.dcp]

puts "X3_CORE_SYNTH_COMPLETE: $out_dir"
