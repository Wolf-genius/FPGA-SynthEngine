set root [file dirname [file normalize [info script]]]
cd $root
open_project [file join $root eight_key_instrument_display.gprj]
set_option -top_module eight_key_instrument_display_top
set_option -use_cpu_as_gpio 1
set_option -route_maxfan 60
run all
