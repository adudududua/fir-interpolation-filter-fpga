# Isolated clock-topology feasibility experiment for Vivado 2025.2.
# Generated reports/checkpoints are kept below tools/.../_work/structure_redesign.

set script_dir [file normalize [file dirname [info script]]]
set work_dir [file normalize [file join $script_dir .. _work structure_redesign clock256_feasibility]]
file mkdir $work_dir

set part_name xc7a35tfgg484-2
set top_name dual_family_clock_256x_candidate
set rtl_file [file join $script_dir dual_family_clock_256x_candidate.v]

read_verilog $rtl_file

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt
create_clock -name clk_20m -period 50.000 [get_ports clk_20m]

# The two MMCM outputs are selected by BUFGMUX_CTRL and can never be active on
# the downstream clock tree at the same time.  Model the same reset-protected
# family switch protocol used by the formal board project.
set clk_44k1_256 [get_clocks -of_objects [get_pins u_mmcm_44k1/CLKOUT0]]
set clk_48k_256 [get_clocks -of_objects [get_pins u_mmcm_48k/CLKOUT0]]
# BUFR creates one derived 128x clock for each possible MMCM master.  Include
# those descendants explicitly; grouping only the two masters leaves false
# cross-family paths between the two clocks on the same downstream registers.
set clk_44k1_128 [get_clocks clk_audio_128x]
set clk_48k_128 [get_clocks clk_audio_128x_1]
set_clock_groups -logically_exclusive \
    -group [get_clocks [list $clk_44k1_256 $clk_44k1_128]] \
    -group [get_clocks [list $clk_48k_256 $clk_48k_128]]
set_false_path -from [get_ports reset]
set_false_path -from [get_ports family_48k]
set_false_path -to [get_pins -hierarchical -regexp \
    {.*u_bufgmux_compute_family/S[01]}]
write_checkpoint -force [file join $work_dir post_synth.dcp]
report_utilization -file [file join $work_dir post_synth_utilization.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $work_dir post_route.dcp]

report_utilization -file [file join $work_dir post_route_utilization.rpt]
report_clock_utilization -file [file join $work_dir clock_utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -max_paths 20 -input_pins -file [file join $work_dir timing_summary.rpt]
report_drc -file [file join $work_dir drc.rpt]

set error_violations [get_drc_violations -quiet -filter {SEVERITY == Error}]
set critical_violations [get_drc_violations -quiet -filter {SEVERITY == Critical_Warning}]
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : 0.0}]
set whs [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : 0.0}]
set result_file [open [file join $work_dir result.txt] w]
puts $result_file "CLOCK256_FEASIBILITY=ROUTED"
puts $result_file "DRC_ERROR_COUNT=[llength $error_violations]"
puts $result_file "DRC_CRITICAL_WARNING_COUNT=[llength $critical_violations]"
puts $result_file "MMCM_COUNT=[llength [get_cells -hier -filter {REF_NAME =~ MMCME2*}]]"
puts $result_file "BUFGCTRL_COUNT=[llength [get_cells -hier -filter {REF_NAME == BUFGCTRL}]]"
puts $result_file "BUFR_COUNT=[llength [get_cells -hier -filter {REF_NAME == BUFR}]]"
puts $result_file "WNS_NS=$wns"
puts $result_file "WHS_NS=$whs"
close $result_file

if {[llength $error_violations] != 0} {
    error "Clock256 candidate routed but has DRC errors; see $work_dir/drc.rpt"
}
if {$wns < 0.0 || $whs < 0.0} {
    error "Clock256 candidate has negative timing slack: WNS=$wns WHS=$whs"
}

puts "CLOCK256_FEASIBILITY_PASS"
puts "RESULT_DIR=$work_dir"
