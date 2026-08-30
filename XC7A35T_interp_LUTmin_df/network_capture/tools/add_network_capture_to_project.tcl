set script_dir [file dirname [file normalize [info script]]]
set feature_dir [file normalize [file join $script_dir ..]]
set project_dir [file normalize [file join $feature_dir ..]]
set project_file [file join $project_dir XC7A35T_interp.xpr]

open_project $project_file

set rtl_files [glob -nocomplain [file join $feature_dir rtl *.v]]
foreach rtl $rtl_files {
    if {[llength [get_files -quiet $rtl]] == 0} {
        add_files -fileset sources_1 -norecurse $rtl
    }
}
update_compile_order -fileset sources_1
set_property top board_demo_competition_dac8_top [get_filesets sources_1]
# Vivado 2025.2 会在 add_files/update_compile_order 时自动写回当前 XPR；
# `save_project` 在该版本被解析为需要 name 的 save_project_as，不能再调用。
close_project
