# Vivado 2025.2 的用户 Tcl Store 目录损坏时，基础命令（read_verilog、
# current_fileset 等）也可能错误触发 appinit 加载。本脚本在业务脚本之前
# 把安装目录中的 support 包显式加入 auto_path 并预加载，绕开损坏的目录。
set vivado_install_store [file normalize [file join $::env(XILINX_VIVADO) data XilinxTclStore]]
set required_app_dirs {}
# 把安装目录中所有厂商/仿真器 app 的 pkgIndex 加入搜索路径；read_verilog
# 会枚举这些后端，即使本次综合并不使用它们。
foreach vendor_dir [glob -nocomplain -types d \
        -directory [file join $vivado_install_store tclapp] *] {
    foreach app_dir [glob -nocomplain -types d -directory $vendor_dir *] {
        if {[file exists [file join $app_dir pkgIndex.tcl]]} {
            lappend required_app_dirs $app_dir
        }
    }
}
foreach support_dir [concat [list \
    [file join $vivado_install_store support] \
    [file join $vivado_install_store support appinit]] $required_app_dirs] {
    if {[lsearch -exact $::auto_path $support_dir] < 0} {
        lappend ::auto_path $support_dir
    }
}
package require ::tclapp::support::appinit 1.2
# read_verilog 会按需加载多种仿真器 Tcl app。用户 Tcl Store catalog 损坏时，
# appinit 不一定能自动定位它们；auto_path 已显式指向安装目录，无需改用户目录。
if {[llength $argv] == 0} {
    error "用法：vivado_tclstore_workaround.tcl <后续脚本>"
}
set downstream_script [file normalize [lindex $argv 0]]
source $downstream_script
