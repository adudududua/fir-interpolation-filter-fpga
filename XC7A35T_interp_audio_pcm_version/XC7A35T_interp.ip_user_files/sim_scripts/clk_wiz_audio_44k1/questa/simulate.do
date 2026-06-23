onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib clk_wiz_audio_44k1_opt

do {wave.do}

view wave
view structure
view signals

do {clk_wiz_audio_44k1.udo}

run -all

quit -force
