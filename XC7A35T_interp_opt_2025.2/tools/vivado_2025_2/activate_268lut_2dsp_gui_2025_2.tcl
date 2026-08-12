set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set synth_pre_hook [file join $script_dir synth_low_memory_pre.tcl]

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

puts "ACTIVATE_PROJECT=$project_file"
open_project $project_file
set_param general.maxThreads 1

set source_generics [get_property GENERIC [get_filesets sources_1]]
require_condition \
    [expr {[lsearch -exact $source_generics \
        "USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=0"] >= 0}] \
    "The project does not select the 268-LUT / 2-DSP CIC mapping."
require_condition \
    [expr {[lsearch -exact $source_generics \
        "USE_NATIONAL_FINALS_STAGE2_DATA_W=20"] >= 0}] \
    "The project does not retain Stage2 signed-20 data."

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY full $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.SHREG_MIN_SIZE 5 $synth_run
set_property STEPS.SYNTH_DESIGN.TCL.PRE $synth_pre_hook $synth_run
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea $impl_run
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl_run

# Invalidate the prior 3-DSP GUI run products so a manual Generate Bitstream
# cannot silently reuse stale synth_1/impl_1 output after switching mode.
reset_run $impl_run
reset_run $synth_run

puts "ACTIVE_GUI_CIC_INTEGRATOR_DSP_MODE=0"
puts "ACTIVE_GUI_SYNTH_STATUS=[get_property STATUS $synth_run]"
puts "ACTIVE_GUI_IMPL_STATUS=[get_property STATUS $impl_run]"
puts "ACTIVE_268LUT_2DSP_GUI_CONFIGURATION_PASS"

close_project
exit
