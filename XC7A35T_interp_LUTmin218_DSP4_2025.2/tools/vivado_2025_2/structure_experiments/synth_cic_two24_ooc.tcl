set script_dir [file normalize [file dirname [info script]]]
set_param general.maxThreads 1
set project_dir [file normalize [file join $script_dir ../../..]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set variant [expr {$argc > 0 ? [lindex $argv 0] : "baseline"}]

if {$variant eq "baseline"} {
    set top_name baseline_cic_ooc_wrapper
} elseif {$variant eq "candidate"} {
    set top_name candidate_cic_two24_ooc_wrapper
} elseif {$variant eq "sequential_pair"} {
    set top_name candidate_cic_sequential_pair_ooc_wrapper
} elseif {$variant eq "simultaneous"} {
    set top_name candidate_cic_simultaneous_ooc_wrapper
} else {
    error "variant must be baseline, candidate, sequential_pair, or simultaneous"
}

set work_dir [file normalize [file join $script_dir .. _work post221_4dsp_2bram cic_two24_ooc $variant]]
file mkdir $work_dir

set sources [list \
    [file join $source_root all2x_v6 round_sat_shift_compact.v] \
    [file join $source_root national_finals cic_interp16_n3_hold2_dsp_ce.v] \
    [file join $script_dir cic_interp16_n3_hold2_two24_comb_integrator_ce.v] \
    [file join $script_dir cic_interp16_n3_hold2_two24_simultaneous_ce.v] \
    [file join $script_dir cic_interp16_n3_hold2_two24_sequential_pair_ce.v] \
    [file join $script_dir cic_two24_ooc_wrappers.v]]

read_verilog $sources
synth_design -top $top_name -part xc7a35tfgg484-2 \
    -mode out_of_context -flatten_hierarchy full \
    -directive AreaOptimized_high -resource_sharing on -shreg_min_size 5
create_clock -name cic_clk -period 162.760 [get_ports clk]

set utilization [report_utilization -return_string]
report_utilization -file [file join $work_dir utilization_post_synth.rpt]
report_utilization -hierarchical -hierarchical_min_primitive_count 0 \
    -file [file join $work_dir utilization_hierarchical_post_synth.rpt]
write_checkpoint -force [file join $work_dir post_synth.dcp]

regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} $utilization unused lut_count
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} $utilization unused ff_count
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]

set fid [open [file join $work_dir result.txt] w]
puts $fid "VARIANT=$variant"
puts $fid "STAGE=POST_SYNTH"
puts $fid "LUT=$lut_count"
puts $fid "FF=$ff_count"
puts $fid "DSP48E1=$dsp_count"
puts $fid "RAMB18E1=$bram18_count"
close $fid

puts "CIC_VARIANT=$variant"
puts "CIC_LUT=$lut_count"
puts "CIC_FF=$ff_count"
puts "CIC_DSP=$dsp_count"
puts "CIC_RAMB18=$bram18_count"
