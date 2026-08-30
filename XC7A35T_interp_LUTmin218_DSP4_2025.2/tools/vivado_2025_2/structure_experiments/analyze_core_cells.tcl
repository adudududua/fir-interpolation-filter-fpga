set script_dir [file dirname [file normalize [info script]]]
set default_dcp [file normalize [file join $script_dir .. core_ooc results 20260810_184031 core_post_route.dcp]]
set dcp_path $default_dcp
set output_path [file normalize [file join $script_dir core_cell_breakdown.txt]]

if {$argc >= 1} {
    set dcp_path [file normalize [lindex $argv 0]]
}
if {$argc >= 2} {
    set output_path [file normalize [lindex $argv 1]]
}

open_checkpoint $dcp_path

proc primitive_group_count {cells ref_pattern} {
    return [llength [filter $cells "REF_NAME =~ $ref_pattern"]]
}

set groups {
    {stage1 {*stage1*}}
    {stage23 {*stage23*}}
    {cic {*cic*}}
    {coeff {*coeff*}}
    {top_all {*}}
}

set fid [open $output_path w]
puts $fid "DCP=$dcp_path"
puts $fid "GROUP LUT FF CARRY4 DSP48E1 RAMB18E1 TOTAL_PRIMITIVES"

foreach group $groups {
    lassign $group label name_pattern
    if {$label eq "top_all"} {
        set cells [get_cells -quiet -hierarchical -filter {IS_PRIMITIVE}]
    } else {
        set cells [get_cells -quiet -hierarchical -filter "IS_PRIMITIVE && NAME =~ $name_pattern"]
    }
    set lut_count 0
    foreach lut_ref {LUT1 LUT2 LUT3 LUT4 LUT5 LUT6 LUT6_2} {
        incr lut_count [primitive_group_count $cells $lut_ref]
    }
    set ff_count 0
    foreach ff_ref {FDRE FDSE FDCE FDPE FDRSE FDCPE} {
        incr ff_count [primitive_group_count $cells $ff_ref]
    }
    puts $fid [format "%s %d %d %d %d %d %d" \
        $label \
        $lut_count \
        $ff_count \
        [primitive_group_count $cells CARRY4] \
        [primitive_group_count $cells DSP48E1] \
        [primitive_group_count $cells RAMB18E1] \
        [llength $cells]]
}

puts $fid ""
puts $fid "DSP_CELLS"
foreach cell [get_cells -quiet -hierarchical -filter {REF_NAME == DSP48E1}] {
    puts $fid $cell
}
puts $fid ""
puts $fid "RAMB18_CELLS"
foreach cell [get_cells -quiet -hierarchical -filter {REF_NAME == RAMB18E1}] {
    puts $fid $cell
}

close $fid
close_design
puts "CORE_CELL_BREAKDOWN=$output_path"
