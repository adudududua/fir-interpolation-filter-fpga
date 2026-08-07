set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]
set report_dir [file join $script_dir evidence preparation]
file mkdir $report_dir

puts "PREPARE_PROJECT=$project_file"
open_project $project_file

# Keep memory and process pressure predictable on this 16 GB host.
set_param general.maxThreads 4

set ips [get_ips -quiet *]
report_ip_status -file [file join $report_dir ip_status_before_upgrade.rpt]
if {[llength $ips] > 0} {
    puts "PREPARE_IPS=$ips"
    upgrade_ip $ips
    generate_target all $ips
}
report_ip_status -file [file join $report_dir ip_status_after_upgrade.rpt]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]

# Preserve the signed-off P3-U synthesis profile and use the Vivado 2025.2
# area-oriented implementation directive validated by the strategy audit.
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY full $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on $synth_run
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreArea $impl_run
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl_run

# Reset through Vivado so source files and project metadata are preserved.
reset_run $impl_run
reset_run $synth_run

puts "PREPARE_SYNTH_DIRECTIVE=[get_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $synth_run]"
puts "PREPARE_FLATTEN=[get_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $synth_run]"
puts "PREPARE_RESOURCE_SHARING=[get_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING $synth_run]"
puts "PREPARE_OPT_DIRECTIVE=[get_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts "PREPARE_PLACE_DIRECTIVE=[get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts "PREPARE_PROJECT_2025_2_PASS"

close_project
exit
