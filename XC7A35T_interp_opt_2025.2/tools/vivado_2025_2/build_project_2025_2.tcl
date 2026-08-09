set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set result_dir [expr {$argc > 0 ? [file normalize [lindex $argv 0]] : [file join $script_dir results latest]}]
set jobs [expr {$argc > 1 ? [lindex $argv 1] : 2}]
file mkdir $result_dir

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

proc wait_for_run_complete {run_name timeout_seconds} {
    set deadline [expr {[clock seconds] + $timeout_seconds}]
    while {1} {
        wait_on_run $run_name
        set run_object [get_runs $run_name]
        set run_progress [get_property PROGRESS $run_object]
        set run_status [get_property STATUS $run_object]
        puts "RUN_STATE name=$run_name progress=$run_progress status=$run_status"
        if {$run_progress eq "100%"} {
            return
        }
        if {[regexp -nocase {error|fail|cancel} $run_status]} {
            error "$run_name failed: status='$run_status', progress='$run_progress'"
        }
        if {[clock seconds] >= $deadline} {
            error "$run_name timed out: status='$run_status', progress='$run_progress'"
        }
        after 1000
    }
}

puts "BUILD_PROJECT=$project_file"
puts "BUILD_RESULT_DIR=$result_dir"
puts "BUILD_JOBS=$jobs"
open_project $project_file
set_param general.maxThreads $jobs

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY full $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on $synth_run
# The only inferred SRL is a four-cycle reset-release delay chain.  Keeping
# it in FFs removes one LUTRAM while preserving the exact cycle latency.
set_property STEPS.SYNTH_DESIGN.ARGS.SHREG_MIN_SIZE 5 $synth_run
# ExploreArea + Explore is the reproducible LUT-first implementation pair for
# the current 2025.2 source tree.  Stage1 keeps its reset-zero center-delay
# register unchanged while invalid startup reads are expressed as a register
# enable, removing the 24-bit BRAM-data/zero mux.  Together with the CIC DSP
# role exchange, the release target is no more than 239 LUT while keeping
# 4 DSP / 4 RAMB18E1; the hard gates below prevent stale or wrong-run results.
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea $impl_run
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl_run

reset_run $synth_run
launch_runs $synth_run -jobs $jobs
wait_for_run_complete synth_1 1200
require_condition [expr {[get_property PROGRESS $synth_run] eq "100%"}] \
    "synth_1 did not complete."

open_run synth_1
report_utilization -file [file join $result_dir utilization_synthesized.rpt]
close_design

reset_run $impl_run
launch_runs $impl_run -to_step write_bitstream -jobs $jobs
wait_for_run_complete impl_1 1800
require_condition [expr {[get_property PROGRESS $impl_run] eq "100%"}] \
    "impl_1 did not complete through write_bitstream."

open_run impl_1
set utilization_report [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $result_dir timing_summary_routed.rpt]
report_route_status -file [file join $result_dir route_status_routed.rpt]
report_drc -file [file join $result_dir drc_routed.rpt]
check_timing -verbose -file [file join $result_dir check_timing_routed.rpt]
report_power -file [file join $result_dir power_routed.rpt]
write_checkpoint -force [file join $result_dir board_routed_2025_2.dcp]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused lut_count] \
    "Could not parse Slice LUT count."
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization_report unused ff_count] \
    "Could not parse Slice Register count."

set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]]
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
require_condition [expr {[llength $setup_path] == 1}] "No setup timing path was found."
require_condition [expr {[llength $hold_path] == 1}] "No hold timing path was found."
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set bit_file [file join [get_property DIRECTORY $impl_run] board_demo_competition_dac8_top.bit]
require_condition [file exists $bit_file] "Expected bitstream is missing: $bit_file"
file copy -force $bit_file [file join $result_dir board_demo_competition_dac8_top_2025_2.bit]

puts "V2025_2_LUT=$lut_count"
puts "V2025_2_FF=$ff_count"
puts "V2025_2_DSP=$dsp_count"
puts "V2025_2_BRAM18=$bram18_count"
puts "V2025_2_MMCM=$mmcm_count"
puts "V2025_2_WNS=$wns"
puts "V2025_2_WHS=$whs"
puts "V2025_2_DRC_ERRORS=[llength $drc_errors]"

require_condition [expr {$dsp_count == 4}] "Expected exactly 4 DSP48E1 cells."
require_condition [expr {$bram18_count == 4}] "Expected exactly 4 RAMB18E1 cells."
require_condition [expr {$mmcm_count == 2}] "Expected exactly 2 MMCME2_ADV cells."
require_condition [expr {$lut_count <= 239}] \
    "LUT regression: expected no more than 239, got $lut_count."
require_condition [expr {$ff_count <= 390}] \
    "FF regression: expected no more than 390, got $ff_count."
require_condition [expr {$wns >= 0.0}] "Setup timing failed: WNS=$wns ns."
require_condition [expr {$whs >= 0.0}] "Hold timing failed: WHS=$whs ns."
require_condition [expr {[llength $drc_errors] == 0}] \
    "DRC contains [llength $drc_errors] error(s)."

puts "VIVADO_2025_2_FULL_BUILD_PASS"
close_design
close_project
exit
