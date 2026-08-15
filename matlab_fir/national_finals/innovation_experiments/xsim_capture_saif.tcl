set saif_path [file normalize $::env(NF_SAIF_PATH)]
open_saif $saif_path
log_saif [get_objects -r /tb_board_postroute_dac_activity/dut/*]
run all
close_saif
quit
