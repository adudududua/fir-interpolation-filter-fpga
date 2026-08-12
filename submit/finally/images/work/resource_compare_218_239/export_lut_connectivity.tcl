if {$argc != 2} {
    error "usage: vivado -mode batch -source export_lut_connectivity.tcl -tclargs <routed.dcp> <output.tsv>"
}

set checkpoint [file normalize [lindex $argv 0]]
set output_file [file normalize [lindex $argv 1]]

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

proc cell_records {cells} {
    set records {}
    foreach cell [lsort -unique $cells] {
        set name [get_property NAME $cell]
        set ref_name [get_property REF_NAME $cell]
        set file_name [get_property FILE_NAME $cell]
        lappend records "$name|$ref_name|$file_name"
    }
    return [join $records ";"]
}

open_checkpoint $checkpoint
set fid [open $output_file w]
puts $fid "CELL\tLOC\tBEL\tFILE_NAME\tLINE_NUMBER\tSTARTPOINT_CELLS\tENDPOINT_CELLS"

foreach cell [lsort [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]] {
    set input_pins [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]
    set output_pins [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
    set start_pins {}
    set endpoint_pins {}
    if {[llength $input_pins] > 0} {
        set start_pins [all_fanin -quiet -flat -startpoints_only -to $input_pins]
    }
    if {[llength $output_pins] > 0} {
        set endpoint_pins [all_fanout -quiet -flat -endpoints_only -from $output_pins]
    }
    set start_cells [get_cells -quiet -of_objects $start_pins]
    set endpoint_cells [get_cells -quiet -of_objects $endpoint_pins]
    puts $fid "[get_property NAME $cell]\t[get_property LOC $cell]\t[get_property BEL $cell]\t[get_property FILE_NAME $cell]\t[get_property LINE_NUMBER $cell]\t[cell_records $start_cells]\t[cell_records $endpoint_cells]"
}

close $fid
close_design
exit
