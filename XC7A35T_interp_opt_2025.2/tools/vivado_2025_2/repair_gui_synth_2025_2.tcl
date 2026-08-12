set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set pre_hook [file join $script_dir synth_low_memory_pre.tcl]
set result_dir [expr {$argc > 0 \
    ? [file normalize [lindex $argv 0]] \
    : [file join $script_dir results manual_synth_repair]}]
file mkdir $result_dir

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

puts "REPAIR_PROJECT=$project_file"
puts "REPAIR_PRE_HOOK=$pre_hook"
puts "REPAIR_RESULT_DIR=$result_dir"

open_project $project_file
set_param general.maxThreads 1

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]

# Keep the ordinary GUI run on the same signed-off profile as the formal
# in-memory build, and install a persistent pre-hook for future GUI reruns.
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY full $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.SHREG_MIN_SIZE 5 $synth_run
set_property STEPS.SYNTH_DESIGN.TCL.PRE $pre_hook $synth_run
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea $impl_run
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl_run

# Reset through Vivado so no source, constraint, IP or project metadata is
# deleted.  impl_1 is reset first because it depends on synth_1.
reset_run $impl_run
reset_run $synth_run

puts "REPAIR_SYNTH_PRE=[get_property STEPS.SYNTH_DESIGN.TCL.PRE $synth_run]"
puts "REPAIR_SYNTH_DIRECTIVE=[get_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $synth_run]"
puts "REPAIR_SYNTH_FLATTEN=[get_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $synth_run]"
puts "REPAIR_SYNTH_SHARING=[get_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING $synth_run]"

launch_runs $synth_run -jobs 1
wait_on_run $synth_run

set status [get_property STATUS $synth_run]
set progress [get_property PROGRESS $synth_run]
puts "REPAIR_SYNTH_STATUS=$status"
puts "REPAIR_SYNTH_PROGRESS=$progress"
require_condition [expr {$progress eq "100%"}] \
    "synth_1 did not complete: status=$status progress=$progress"

open_run $synth_run
set utilization [report_utilization -return_string]
report_utilization -file [file join $result_dir utilization_synthesized.rpt]
write_checkpoint -force [file join $result_dir board_synthesized_2025_2.dcp]

require_condition \
    [regexp {\|\s*Slice LUTs[^|]*\|\s*([0-9]+)\s*\|} \
        $utilization unused lut_count] \
    "Could not parse synthesized Slice LUT count."
require_condition \
    [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
        $utilization unused ff_count] \
    "Could not parse synthesized Slice Register count."

set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]]
set bram18_count [llength [get_cells -hierarchical -filter {REF_NAME == RAMB18E1}]]
set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME == MMCME2_ADV}]]

puts "REPAIR_SYNTH_LUT=$lut_count"
puts "REPAIR_SYNTH_FF=$ff_count"
puts "REPAIR_SYNTH_DSP=$dsp_count"
puts "REPAIR_SYNTH_BRAM18=$bram18_count"
puts "REPAIR_SYNTH_MMCM=$mmcm_count"

require_condition [expr {$dsp_count == 2}] "Expected exactly 2 DSP48E1 cells."
require_condition [expr {$bram18_count == 4}] "Expected exactly 4 RAMB18E1 cells."
require_condition [expr {$mmcm_count == 2}] "Expected exactly 2 MMCME2_ADV cells."
require_condition [expr {$lut_count <= 329}] \
    "Synthesis LUT regression: expected no more than 329, got $lut_count."
require_condition [expr {$ff_count <= 425}] \
    "Synthesis FF regression: expected no more than 425, got $ff_count."

puts "REPAIR_GUI_SYNTH_2025_2_PASS"
close_design
close_project
exit
