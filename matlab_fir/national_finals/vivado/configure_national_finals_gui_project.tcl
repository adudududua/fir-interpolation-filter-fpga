# Lock the checked-in Vivado GUI simulation to the same topology as the
# national-finals command-line regression.  Synthesis generics are verified,
# not silently rewritten, so an accidental hardware configuration change
# fails before the GUI opens.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]

proc require_condition {condition message} {
    if {!$condition} {
        error $message
    }
}

proc require_generic {generic_text name value} {
    set expected "${name}=${value}"
    require_condition \
        [expr {[lsearch -exact $generic_text $expected] >= 0}] \
        "GUI project generic mismatch: expected $expected"
}

open_project $project_file

set source_set [get_filesets sources_1]
set project_generics [get_property generic $source_set]
require_generic $project_generics USE_NATIONAL_FINALS_DATAPATH 1
require_generic $project_generics USE_NATIONAL_FINALS_SERIAL_CIC_COMB 1
require_generic $project_generics USE_NATIONAL_FINALS_N3_HOLD_EQUIV 1
require_generic $project_generics USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY 1
require_generic $project_generics USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1 1
require_generic $project_generics USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER 1
require_generic $project_generics USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE 0
require_generic $project_generics USE_NATIONAL_FINALS_NARROW_STAGE23 1

set signedoff_sim_defines [list \
    NATIONAL_FINALS \
    NATIONAL_FINALS_USE_SERIAL_CIC_COMB \
    NATIONAL_FINALS_USE_N3_HOLD \
    NATIONAL_FINALS_USE_STAGE1_DSP48_PREADDER \
    NATIONAL_FINALS_NARROW_STAGE23 \
    PHASE7_USE_LUTRAM_STAGE23 \
    PHASE7_USE_BRAM_STAGE23_HISTORY \
    NATIONAL_FINALS_UNIFIED_STAGE23_HISTORY \
    NATIONAL_FINALS_SINGLE_BRAM_STAGE1 \
    PHASE7_USE_BRAM_STAGE23_COEFF]

set sim_set [get_filesets sim_1]
set_property top tb_phase7_full_chain_bittrue $sim_set
set_property verilog_define $signedoff_sim_defines $sim_set
update_compile_order -fileset sim_1

puts "NATIONAL_FINALS_GUI_SIM_CONFIGURED"
puts "GUI_SIM_TOP=[get_property top $sim_set]"
puts "GUI_SIM_DEFINES=[get_property verilog_define $sim_set]"

close_project
