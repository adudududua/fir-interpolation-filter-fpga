# Resource lower-bound checkpoint for the imported, functionally proven X3
# shared-FIR seed.  This is deliberately isolated from the formal project.

set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ../../..]]
set source_root [file join $project_dir XC7A35T_interp.srcs sources_1 new]
set work_dir [file normalize [file join $script_dir .. _work structure_redesign shared_fir256_seed]]
file mkdir $work_dir

set sources [list \
    [file join $source_root all2x_v6 round_sat_shift_compact.v] \
    [file join $source_root all2x_v6 bridge_valid_quantized_to_interp2_ce.v] \
    [file join $source_root national_finals nf_unified_fir_coeff_bram.v] \
    [file join $source_root national_finals experiments nf_interp_fir3_shared_preg_256x_ce.v]]

read_verilog $sources
synth_design -top nf_interp_fir3_shared_preg_256x_ce \
    -part xc7a35tfgg484-2 -mode out_of_context \
    -flatten_hierarchy full -directive AreaOptimized_high \
    -resource_sharing on -shreg_min_size 5
create_clock -name compute_256x -period 81.380 [get_ports clk]

set utilization [report_utilization -return_string]
report_utilization -file [file join $work_dir utilization_post_synth.rpt]
report_timing_summary -max_paths 20 -file [file join $work_dir timing_post_synth.rpt]
write_checkpoint -force [file join $work_dir post_synth.dcp]

regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} $utilization unused lut_count
regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} $utilization unused ff_count
set dsp_count [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]

set fid [open [file join $work_dir result.txt] w]
puts $fid "STAGE=POST_SYNTH"
puts $fid "LUT=$lut_count"
puts $fid "FF=$ff_count"
puts $fid "DSP48E1=$dsp_count"
puts $fid "RAMB18E1=$bram18_count"
close $fid

puts "SHARED_FIR256_SEED_LUT=$lut_count"
puts "SHARED_FIR256_SEED_FF=$ff_count"
puts "SHARED_FIR256_SEED_DSP=$dsp_count"
puts "SHARED_FIR256_SEED_RAMB18=$bram18_count"
