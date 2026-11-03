onerror {quit -code 1 -f}
vlib terminal_work
vlog -work terminal_work -sv ../../topic1_student_reference/project_code/dependencies/lesson36_build/al_ip/afifo_32_16_256.v ../../topic1_student_reference/project_code/dependencies/lesson36_build/src/fifo_prefetch_2.v ../../topic1_student_reference/project_code/dependencies/lesson36_build/src/sync_2ff.v ../../topic1_student_reference/project_code/dependencies/lesson36_build/src/video_timing_ctrl.v ../../topic1_student_reference/project_code/rtl/memory/media_sdram_arbiter.v ../../topic1_student_reference/project_code/rtl/io/uart_tx_byte.v ../src/media_frame_reader.v ../src/media_frame_loader.v ../src/terminal_control.v tb_terminal_memory.sv
vsim -c terminal_work.tb_terminal_memory
onbreak {quit -code 1 -f}
run -all
quit -code 0 -f
