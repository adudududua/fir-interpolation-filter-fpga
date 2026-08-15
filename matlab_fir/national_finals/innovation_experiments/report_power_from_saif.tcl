set dcp_path [file normalize [lindex $argv 0]]
set saif_path [file normalize [lindex $argv 1]]
set report_path [file normalize [lindex $argv 2]]
set summary_path [file normalize [lindex $argv 3]]

open_checkpoint $dcp_path
read_saif $saif_path -strip_path tb_board_postroute_dac_activity/dut
set power_text [report_power -return_string]
report_power -file $report_path

set total_w "NA"
set dynamic_w "NA"
set static_w "NA"
set confidence "NA"
regexp {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $power_text unused total_w
regexp {\|\s*Dynamic \(W\)\s*\|\s*([0-9.]+)} $power_text unused dynamic_w
regexp {\|\s*Device Static \(W\)\s*\|\s*([0-9.]+)} $power_text unused static_w
regexp {\|\s*Confidence Level\s*\|\s*([^|]+)} $power_text unused confidence

set fid [open $summary_path w]
puts $fid "DCP=$dcp_path"
puts $fid "SAIF=$saif_path"
puts $fid "TOTAL_W=$total_w"
puts $fid "DYNAMIC_W=$dynamic_w"
puts $fid "STATIC_W=$static_w"
puts $fid "CONFIDENCE=[string trim $confidence]"
close $fid

puts "SAIF_POWER_TOTAL_W=$total_w"
puts "SAIF_POWER_DYNAMIC_W=$dynamic_w"
puts "SAIF_POWER_STATIC_W=$static_w"
puts "SAIF_POWER_CONFIDENCE=[string trim $confidence]"
close_design
exit
