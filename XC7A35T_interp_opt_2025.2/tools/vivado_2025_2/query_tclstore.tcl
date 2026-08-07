puts "TCL_AUTO_PATH_BEGIN"
foreach path $::auto_path {
    puts $path
}
puts "TCL_AUTO_PATH_END"
puts "RESET_COMMANDS=[info commands ::tclapp::*reset*]"
puts "TCLAPP_COMMANDS=[info commands ::tclapp::*]"
puts "RESET_HELP_BEGIN"
if {[catch {help ::tclapp::reset_tclstore} reset_help]} {
    puts "RESET_HELP_FAIL=$reset_help"
} else {
    puts $reset_help
}
puts "RESET_HELP_END"
if {[catch {package require ::tclapp::support::appinit 1.2} result]} {
    puts "APPINIT_REQUIRE_FAIL=$result"
} else {
    puts "APPINIT_REQUIRE_PASS=$result"
}
exit
