# Lock the checked-in Vivado GUI simulation to the same topology as the
# national-finals command-line regression.  Synthesis generics are verified,
# not silently rewritten, so an accidental hardware configuration change
# fails before the GUI opens.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set project_src_dir [file join $repo_dir XC7A35T_interp_audio_pcm_wordlen_opt \
    XC7A35T_interp.srcs sources_1 new]
set signedoff_wrapper [file join $project_src_dir national_finals \
    nf_signedoff_filter_core.v]
set shared_pcm_stage1 [file join $project_src_dir national_finals \
    nf_pcm_stage1_shared_ramb18_sdp.v]
set daily_vector_dir [file join $repo_dir matlab_fir national_finals \
    vectors daily]

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
require_condition [file exists $signedoff_wrapper] \
    "Signed-off wrapper is missing: $signedoff_wrapper"
require_condition [file exists $shared_pcm_stage1] \
    "Shared PCM/Stage1 RAM source is missing: $shared_pcm_stage1"
if {[llength [get_files -quiet -of_objects $source_set $signedoff_wrapper]] == 0} {
    add_files -fileset sources_1 -norecurse $signedoff_wrapper
}
if {[llength [get_files -quiet -of_objects $source_set $shared_pcm_stage1]] == 0} {
    add_files -fileset sources_1 -norecurse $shared_pcm_stage1
}
set project_generics [get_property generic $source_set]
require_generic $project_generics USE_NATIONAL_FINALS_DATAPATH 1
require_generic $project_generics USE_NATIONAL_FINALS_SERIAL_CIC_COMB 1
require_generic $project_generics USE_NATIONAL_FINALS_N3_HOLD_EQUIV 1
require_generic $project_generics USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY 1
require_generic $project_generics USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1 1
require_generic $project_generics USE_NATIONAL_FINALS_SHARED_PCM_STAGE1_BRAM 1
require_generic $project_generics USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER 1
require_generic $project_generics USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE 2
require_generic $project_generics USE_NATIONAL_FINALS_NARROW_STAGE23 1

set sim_set [get_filesets sim_1]
set daily_vector_names [list \
    impulse_input_24bit.mem \
    impulse_y4_golden_24bit.mem \
    impulse_y8_golden_24bit.mem \
    impulse_y128_golden_24bit.mem \
    random_seed01_input_24bit.mem \
    random_seed01_y4_golden_24bit.mem \
    random_seed01_y8_golden_24bit.mem \
    random_seed01_y128_golden_24bit.mem]
foreach vector_name $daily_vector_names {
    set vector_path [file join $daily_vector_dir $vector_name]
    require_condition [file exists $vector_path] \
        "GUI simulation asset is missing: $vector_path"
    if {[llength [get_files -quiet -of_objects $sim_set $vector_path]] == 0} {
        add_files -fileset sim_1 -norecurse $vector_path
    }
    set vector_file [get_files -quiet -of_objects $sim_set $vector_path]
    set_property file_type {Memory Initialization Files} $vector_file
    set_property used_in_simulation true $vector_file
}
set_property top tb_phase7_full_chain_bittrue $sim_set
set_property verilog_define [list] $sim_set
update_compile_order -fileset sim_1

puts "NATIONAL_FINALS_GUI_SIM_CONFIGURED"
puts "GUI_SIM_TOP=[get_property top $sim_set]"
puts "GUI_SIM_DEFINES=[get_property verilog_define $sim_set]"
puts "GUI_SIM_ASSET_COUNT=[llength $daily_vector_names]"

close_project
