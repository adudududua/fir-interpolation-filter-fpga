# OOC resource comparison for the signed-off low-clock CIC and the
# high-clock two-DSP shared-arithmetic candidate.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set src_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set result_root [file normalize [file join $script_dir .. _work \
    sub300_fast_cic_ooc]]

set top_name cic_interp16_n3_hold2_fast_shared_dsp_ce
set result_tag fast_shared
if {$argc > 0} {
    set top_name [lindex $argv 0]
}
if {$argc > 1} {
    set result_tag [lindex $argv 1]
}
if {$top_name ni {cic_interp16_n3_hold2_dsp_ce \
                  cic_interp16_n3_hold2_fast_shared_dsp_ce}} {
    error "Unsupported CIC OOC top: $top_name"
}
if {![regexp {^[A-Za-z0-9_-]+$} $result_tag]} {
    error "result_tag may contain only letters, digits, underscore, and dash"
}

file mkdir $result_root
set result_dir [file join $result_root $result_tag]
file mkdir $result_dir

read_verilog [file join $src_dir all2x_v6 round_sat_shift_compact.v]
read_verilog [file join $src_dir national_finals \
    cic_interp16_n3_hold2_dsp_ce.v]
read_verilog [file join $src_dir national_finals \
    cic_interp16_n3_hold2_fast_shared_dsp_ce.v]

synth_design -mode out_of_context -top $top_name -part xc7a35tfgg484-2 \
    -directive AreaOptimized_high -flatten_hierarchy rebuilt \
    -resource_sharing on

report_utilization -file [file join $result_dir utilization_synthesized.rpt]
report_utilization -hierarchical \
    -file [file join $result_dir utilization_hierarchical_synthesized.rpt]
report_timing_summary -file [file join $result_dir timing_unconstrained.rpt]
write_checkpoint -force [file join $result_dir ${top_name}_synth.dcp]

puts "SUB300_FAST_CIC_OOC_PASS"
puts "TOP=$top_name"
puts "RESULT_DIR=$result_dir"
