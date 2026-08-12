if {$argc != 2} {
    error "usage: vivado -mode batch -source export_routed_hierarchy.tcl -tclargs <routed.dcp> <output_dir>"
}

set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
file mkdir $output_dir

if {[info exists ::env(XILINX_VIVADO)]} {
    set tcl_store [file join $::env(XILINX_VIVADO) data XilinxTclStore]
    set appinit_dir [file join $tcl_store support appinit]
    set xilinx_apps_dir [file join $tcl_store tclapp xilinx]
    if {[file isdirectory $appinit_dir] && [lsearch -exact $::auto_path $appinit_dir] == -1} {
        lappend ::auto_path $appinit_dir
    }
    foreach app_dir [glob -nocomplain -types d -directory $xilinx_apps_dir *] {
        if {[lsearch -exact $::auto_path $app_dir] == -1} {
            lappend ::auto_path $app_dir
        }
    }
    catch {package require ::tclapp::support::appinit 1.2}
}

open_checkpoint $checkpoint

report_utilization -file [file join $output_dir utilization_routed.rpt]
report_utilization -hierarchical -hierarchical_depth 32 \
    -file [file join $output_dir utilization_hierarchical_depth32.rpt]

set hierarchy_file [open [file join $output_dir hierarchy_cells.tsv] w]
puts $hierarchy_file "INSTANCE\tREF_NAME\tORIG_REF_NAME"
foreach cell [lsort [get_cells -hierarchical -filter {IS_PRIMITIVE == 0}]] {
    set name [get_property NAME $cell]
    set ref_name [get_property REF_NAME $cell]
    set orig_ref_name [get_property ORIG_REF_NAME $cell]
    puts $hierarchy_file "$name\t$ref_name\t$orig_ref_name"
}
close $hierarchy_file

set primitive_file [open [file join $output_dir primitive_cells.tsv] w]
puts $primitive_file "CELL\tREF_NAME\tPRIMITIVE_GROUP\tLOC\tBEL\tFILE_NAME\tLINE_NUMBER"
foreach cell [lsort [get_cells -hierarchical -filter {IS_PRIMITIVE == 1}]] {
    set name [get_property NAME $cell]
    set ref_name [get_property REF_NAME $cell]
    set primitive_group [get_property PRIMITIVE_GROUP $cell]
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    set file_name [get_property FILE_NAME $cell]
    set line_number [get_property LINE_NUMBER $cell]
    puts $primitive_file "$name\t$ref_name\t$primitive_group\t$loc\t$bel\t$file_name\t$line_number"
}
close $primitive_file

set summary_file [open [file join $output_dir checkpoint_identity.txt] w]
puts $summary_file "CHECKPOINT=$checkpoint"
puts $summary_file "PART=[get_property PART [current_design]]"
puts $summary_file "TOP=[get_property TOP [current_design]]"
puts $summary_file "DESIGN_MODE=[get_property DESIGN_MODE [current_design]]"
puts $summary_file "HIERARCHICAL_CELL_COUNT=[llength [get_cells -hierarchical -filter {IS_PRIMITIVE == 0}]]"
puts $summary_file "PRIMITIVE_CELL_COUNT=[llength [get_cells -hierarchical -filter {IS_PRIMITIVE == 1}]]"
close $summary_file

close_design
exit
