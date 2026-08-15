foreach parameter_name [list_param] {
    if {[string match -nocase *seed* $parameter_name] ||
        [string match -nocase *random* $parameter_name]} {
        puts "$parameter_name=[get_param $parameter_name]"
    }
}
exit
