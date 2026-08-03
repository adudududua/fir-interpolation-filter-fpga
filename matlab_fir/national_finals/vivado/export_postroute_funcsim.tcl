# Export a routed checkpoint as a functional simulation netlist.
#
# Usage:
#   vivado -mode batch -source export_postroute_funcsim.tcl \
#       -tclargs <routed.dcp> <output.v>

if {$argc != 2} {
    error "Expected <routed.dcp> <output.v>"
}

set dcp_path [file normalize [lindex $argv 0]]
set output_path [file normalize [lindex $argv 1]]

if {![file exists $dcp_path]} {
    error "Routed checkpoint does not exist: $dcp_path"
}

file mkdir [file dirname $output_path]
open_checkpoint $dcp_path
write_verilog -force -mode funcsim -include_xilinx_libs $output_path
close_design
puts "POSTROUTE_FUNCSIM_EXPORT_PASS"
puts "NETLIST=$output_path"
