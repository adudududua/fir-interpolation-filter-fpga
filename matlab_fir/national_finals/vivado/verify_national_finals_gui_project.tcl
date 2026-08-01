# Verify that the checked-in Vivado GUI project uses the same configuration as
# the national-finals scripted build.  Pass "rebuild" to reset synth_1/impl_1
# or "reimplement" to reuse synth_1 and rerun impl_1 through the ordinary
# project flow.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. .. ..]]
set project_file [file join $repo_dir \
    XC7A35T_interp_audio_pcm_wordlen_opt XC7A35T_interp.xpr]
set requested_action [expr {$argc > 0 ? [lindex $argv 0] : "inspect"}]

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

require_condition \
    [expr {$requested_action in {"inspect" "rebuild" "reimplement"}}] \
    "Action must be inspect, rebuild, or reimplement."

open_project $project_file

set source_set [get_filesets sources_1]
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
set project_sim_defines [get_property verilog_define $sim_set]
require_condition \
    [expr {[get_property top $sim_set] eq "tb_phase7_full_chain_bittrue"}] \
    "GUI sim_1 top must be tb_phase7_full_chain_bittrue."
require_condition \
    [expr {[llength $project_sim_defines] == 0}] \
    "GUI sim_1 must not use macros to select the signed-off topology."

set signedoff_wrapper [get_files -quiet \
    "*national_finals/nf_signedoff_filter_core.v"]
require_condition [expr {[llength $signedoff_wrapper] == 1}] \
    "Signed-off filter wrapper is not registered exactly once."
set daily_asset_patterns [list \
    impulse_input_24bit.mem \
    impulse_y4_golden_24bit.mem \
    impulse_y8_golden_24bit.mem \
    impulse_y128_golden_24bit.mem \
    random_seed01_input_24bit.mem \
    random_seed01_y4_golden_24bit.mem \
    random_seed01_y8_golden_24bit.mem \
    random_seed01_y128_golden_24bit.mem]
foreach asset_name $daily_asset_patterns {
    set asset_file [get_files -quiet -of_objects $sim_set "*$asset_name"]
    require_condition [expr {[llength $asset_file] == 1}] \
        "GUI simulation asset is not registered exactly once: $asset_name"
}

set serial_cic_file [get_files -quiet \
    "*national_finals/cic_interp16_serial_comb_dsp_ce.v"]
set n3_hold_cic_file [get_files -quiet \
    "*national_finals/cic_interp16_n3_hold2_dsp_ce.v"]
set stage23_history_file [get_files -quiet \
    "*national_finals/nf_stage23_history_ramb18_sdp.v"]
set stage1_history_file [get_files -quiet \
    "*national_finals/nf_stage1_history_ramb18_sdp.v"]
set stage1_serial_file [get_files -quiet \
    "*national_finals/interp2_stage1_single_bram_serial_ce.v"]
set shared_pcm_stage1_file [get_files -quiet \
    "*national_finals/nf_pcm_stage1_shared_ramb18_sdp.v"]
require_condition [expr {[llength $serial_cic_file] == 1}] \
    "Serial-comb CIC source is not registered exactly once in sources_1."
require_condition [expr {[llength $n3_hold_cic_file] == 1}] \
    "N=3 Hold CIC source is not registered exactly once in sources_1."
require_condition [expr {[llength $stage23_history_file] == 1}] \
    "Stage2/3 history RAMB18 source is not registered exactly once."
require_condition [expr {[llength $stage1_history_file] == 1}] \
    "Stage1 history RAMB18 source is not registered exactly once."
require_condition [expr {[llength $stage1_serial_file] == 1}] \
    "Stage1 serialized-read source is not registered exactly once."
require_condition [expr {[llength $shared_pcm_stage1_file] == 1}] \
    "Shared PCM/Stage1 RAMB18 source is not registered exactly once."

set gui_resource_sharing [string tolower [get_property \
    STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING [get_runs synth_1]]]
set gui_opt_directive [get_property \
    STEPS.OPT_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]]
require_condition \
    [expr {$gui_resource_sharing in {"on" "1" "true"}}] \
    "GUI synthesis ResourceSharing must be enabled."
require_condition [expr {$gui_opt_directive eq "Default"}] \
    "GUI implementation opt_design directive must be Default."

puts "NATIONAL_FINALS_GUI_CONFIG_PASS"
puts "GUI_GENERICS=$project_generics"
puts "GUI_SIM_DEFINES=$project_sim_defines"
puts "GUI_RESOURCE_SHARING=$gui_resource_sharing"
puts "GUI_OPT_DIRECTIVE=$gui_opt_directive"

if {$requested_action eq "rebuild"} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    require_condition \
        [expr {[get_property PROGRESS [get_runs synth_1]] eq "100%"}] \
        "GUI synth_1 did not complete."

}

if {$requested_action in {"rebuild" "reimplement"}} {
    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    require_condition \
        [expr {[get_property PROGRESS [get_runs impl_1]] eq "100%"}] \
        "GUI impl_1 did not complete."
}

if {[get_property PROGRESS [get_runs impl_1]] eq "100%"} {
    open_run impl_1
    set utilization_report [report_utilization -return_string]
    require_condition \
        [regexp {\|\s*Slice LUTs\s*\|\s*([0-9]+)\s*\|} \
            $utilization_report unused lut_count] \
        "Could not read the Slice LUT count from report_utilization."
    require_condition \
        [regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} \
            $utilization_report unused ff_count] \
        "Could not read the Slice Register count from report_utilization."
    set dsp_count [llength [get_cells -hierarchical \
        -filter {REF_NAME == DSP48E1}]]
    set bram18_count [llength [get_cells -hierarchical \
        -filter {REF_NAME == RAMB18E1}]]
    set mmcm_count [llength [get_cells -hierarchical \
        -filter {REF_NAME == MMCME2_ADV}]]

    puts "GUI_LUT=$lut_count"
    puts "GUI_FF=$ff_count"
    puts "GUI_DSP=$dsp_count"
    puts "GUI_BRAM18=$bram18_count"
    puts "GUI_MMCM=$mmcm_count"

    require_condition [expr {$dsp_count == 4}] \
        "GUI implementation is not the P4-D 4-DSP architecture."
    require_condition [expr {$bram18_count == 3}] \
        "GUI implementation does not use the expected three RAMB18 blocks."
    require_condition [expr {$mmcm_count == 2}] \
        "GUI implementation does not use the expected two MMCMs."
    require_condition [expr {$lut_count <= 500}] \
        "GUI implementation exceeds the 500-LUT P4-E guard."
    require_condition [expr {$ff_count <= 490}] \
        "GUI implementation exceeds the 490-FF P4-E guard."

    puts "NATIONAL_FINALS_GUI_IMPLEMENTATION_PASS"
    close_design
}

close_project
