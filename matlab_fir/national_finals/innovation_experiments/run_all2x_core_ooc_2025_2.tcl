set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../../../XC7A35T_interp_opt_2025.2]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set output_dir [file normalize [lindex $argv 0]]
set clock_period_ns [expr {$argc > 1 ? [lindex $argv 1] : 162.760}]
set jobs [expr {$argc > 2 ? [lindex $argv 2] : 1}]
file mkdir $output_dir

proc require_condition {condition message} {
    if {!$condition} { error $message }
}

set sources [list \
    [file join $source_root all2x_v2 bridge_valid_only_to_interp2_ce.v] \
    [file join $source_root all2x_v6 bridge_valid_quantized_to_interp2_ce.v] \
    [file join $source_root all2x_v6 round_sat_shift_compact.v] \
    [file join $source_root all2x_v3 interp2_stage1_strict_halfband_bram_ce.v] \
    [file join $source_root all2x_v5 round_sat_q15_compact_to24.v] \
    [file join $source_root all2x_v4 interp2_stage23_shared_dsp_ce.v] \
    [file join $source_root all2x_v2 interp2_halfband7_shiftadd_ce.v] \
    [file join $source_root all2x_v2 interp2_all2x_v2_stage_select.v] \
    [file join $source_root round_sat_q16_to24.v] \
    [file join $source_root fir_core_symm_interp2_all2x.v] \
    [file join $source_root interp2_ctrl_ce.v] \
    [file join $source_root interp2_top_symm_ce_all2x.v] \
    [file join $source_root all2x_v6 interp128_all2x_v6_mixed_width_top_ce.v]]
foreach source_file $sources {
    require_condition [file exists $source_file] "Missing RTL: $source_file"
}
read_verilog $sources

set_param general.maxThreads $jobs
synth_design -top interp128_all2x_v6_mixed_width_top_ce \
    -part xc7a35tfgg484-2 -mode out_of_context \
    -include_dirs [list [file join $source_root all2x_v2]] \
    -flatten_hierarchy full -directive AreaOptimized_high \
    -resource_sharing on -shreg_min_size 5
set half_period_ns [expr {$clock_period_ns / 2.0}]
create_clock -name core_clk_scan -period $clock_period_ns \
    -waveform [list 0.0 $half_period_ns] [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y16 [get_ports clk]
set_false_path -from [get_ports rst_n]

report_utilization -file [file join $output_dir utilization_post_synth.rpt]
write_checkpoint -force [file join $output_dir core_post_synth.dcp]
opt_design -directive ExploreArea
place_design -directive Explore
route_design

set utilization [report_utilization -return_string]
report_utilization -file [file join $output_dir utilization_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $output_dir timing_post_route.rpt]
report_route_status -file [file join $output_dir route_status_post_route.rpt]
report_drc -file [file join $output_dir drc_post_route.rpt]
write_checkpoint -force [file join $output_dir core_post_route.dcp]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization unused lut_count] "Could not parse LUT count"
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization unused ff_count] "Could not parse FF count"
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set registers [all_registers -clock [get_clocks core_clk_scan]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1 \
    -from $registers -to $registers]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1 \
    -from $registers -to $registers]
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]

set fid [open [file join $output_dir all2x_core_ooc_summary.txt] w]
puts $fid "TOOL=Vivado 2025.2"
puts $fid "TOP=interp128_all2x_v6_mixed_width_top_ce"
puts $fid "CLOCK_PERIOD_NS=$clock_period_ns"
puts $fid "CLOCK_MHZ=[expr {1000.0/$clock_period_ns}]"
puts $fid "POST_ROUTE_LUT=$lut_count"
puts $fid "POST_ROUTE_FF=$ff_count"
puts $fid "POST_ROUTE_DSP48E1=$dsp_count"
puts $fid "POST_ROUTE_RAMB18E1=$bram18_count"
puts $fid "INTERNAL_WNS_NS=$wns"
puts $fid "INTERNAL_WHS_NS=$whs"
puts $fid "DRC_ERRORS=[llength $drc_errors]"
close $fid

require_condition [expr {$wns >= 0.0}] "Internal setup timing failed"
require_condition [expr {$whs >= 0.0}] "Internal hold timing failed"
require_condition [expr {[llength $drc_errors] == 0}] "DRC errors found"
puts "ALL2X_CORE_OOC_PASS=$lut_count,$ff_count,$dsp_count,$bram18_count,$wns,$whs"
close_design
exit
