onerror {quit -code 1 -f}
vlib ingest_work
vlog -work ingest_work -sv ../src/fat32_volume_scanner.v ../../topic1_student_reference/project_code/rtl/filesystem/fat32_file_streamer.v ../src/bmp_scale_decoder.v ../src/media_frame_loader.v ../src/media_ingest_pipeline.v tb_fat_ingest.sv
vsim -c ingest_work.tb_fat_ingest
onbreak {quit -code 1 -f}
run -all
quit -code 0 -f
