puts "RESET_TCLSTORE_BEGIN"
if {[catch {tclapp::reset_tclstore -force} result options]} {
    puts stderr "RESET_TCLSTORE_FAIL=$result"
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 1
}
puts "RESET_TCLSTORE_RESULT=$result"
puts "RESET_TCLSTORE_PASS"
exit
