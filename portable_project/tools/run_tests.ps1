param(
 [ValidateSet('All','Control','Scale','Ingest','IngestRetry','Memory','AudioStreamer','AudioPlayer','MediaAssets','Overlay','SectorArbiter','SectorReplay','LoadContention','Safety','Fallback','SafetyOverlay','Plan','Recovery')][string]$Test='All',
 [string]$Iverilog='D:\iverilog\bin\iverilog.exe',
 [string]$Vvp='D:\iverilog\bin\vvp.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$base=Join-Path (Split-Path $root -Parent) 'topic1_student_reference\project_code'
if(Test-Path (Join-Path $root 'dependencies\rtl')){$base=Join-Path $root 'dependencies'}
$src=Join-Path $root 'src'
$sim=Join-Path $root 'sim'
$out=Join-Path $sim 'results'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$cases=@{
 Safety=@("$src\terminal_safety.v","$src\terminal_control.v","$base\rtl\io\uart_tx_byte.v","$sim\tb_terminal_safety.sv")
 Fallback=@("$src\terminal_alarm_fallback.v","$sim\tb_alarm_fallback.sv")
 SafetyOverlay=@("$src\terminal_safety_overlay.v","$src\terminal_safety_font.v","$src\terminal_overlay.v","$src\terminal_text_rom.v","$sim\tb_safety_overlay.sv")
 Control=@("$src\terminal_control.v","$src\terminal_keys.v","$src\terminal_sevenseg.v","$base\dependencies\lesson36_build\src\button_event.v","$base\rtl\io\uart_tx_byte.v","$sim\tb_terminal_control.sv")
 Scale=@("$src\bmp_scale_decoder.v","$src\media_frame_loader.v","$sim\tb_scale_load.sv")
 Ingest=@("$src\fat32_volume_scanner.v","$src\fat32_audio_streamer.v","$src\media_sector_arbiter.v","$base\rtl\filesystem\fat32_file_streamer.v","$src\bmp_scale_decoder.v","$src\media_frame_loader.v","$src\media_ingest_pipeline.v","$sim\tb_fat_ingest.sv")
 Memory=@("$base\dependencies\lesson36_build\al_ip\afifo_32_16_256.v","$base\dependencies\lesson36_build\src\fifo_prefetch_2.v","$base\dependencies\lesson36_build\src\sync_2ff.v","$base\dependencies\lesson36_build\src\video_timing_ctrl.v","$base\rtl\memory\media_sdram_arbiter.v","$base\rtl\io\uart_tx_byte.v","$src\media_frame_reader.v","$src\media_frame_loader.v","$src\terminal_control.v","$sim\tb_terminal_memory.sv")
 AudioStreamer=@("$src\fat32_audio_streamer.v","$sim\tb_fat32_audio_streamer.sv")
 AudioPlayer=@("$base\dependencies\lesson36_build\src\sync_2ff.v","$src\tf_pcm_audio_player.v","$sim\tb_tf_pcm_audio_player.sv")
 Overlay=@("$src\terminal_overlay.v","$src\terminal_text_rom.v","$sim\tb_terminal_overlay.sv")
 SectorArbiter=@("$src\media_sector_arbiter.v","$sim\tb_media_sector_arbiter.sv")
 SectorReplay=@("$src\sd_sector_replay_buffer.v","$sim\tb_sector_replay.sv")
 LoadContention=@("$base\dependencies\lesson36_build\al_ip\afifo_32_16_256.v","$base\dependencies\lesson36_build\src\fifo_prefetch_2.v","$base\dependencies\lesson36_build\src\video_timing_ctrl.v","$base\rtl\memory\media_sdram_arbiter.v","$src\media_frame_reader.v","$src\media_frame_loader.v","$sim\tb_load_contention.sv")
 MediaAssets=@("$base\dependencies\lesson36_build\al_ip\afifo_32_16_256.v","$base\dependencies\lesson36_build\src\sync_2ff.v","$src\tf_pcm_audio_player.v","$src\fat32_volume_scanner.v","$src\fat32_audio_streamer.v","$src\media_sector_arbiter.v","$base\rtl\filesystem\fat32_file_streamer.v","$src\bmp_scale_decoder.v","$src\media_frame_loader.v","$src\media_ingest_pipeline.v","$src\sd_sector_replay_buffer.v","$src\media_ingest_frontend.v","$src\media_storage_ingest_top.v","$sim\tb_media_assets.sv")
 Plan=@("$src\terminal_control.v","$src\terminal_safety.v","$base\rtl\io\uart_tx_byte.v","$sim\tb_plan_config.sv")
 Recovery=@("$src\terminal_media_recovery.v","$sim\tb_media_recovery.sv")
}
$tops=@{Control='tb_terminal_control';Scale='tb_scale_load';Ingest='tb_fat_ingest';Memory='tb_terminal_memory';AudioStreamer='tb_fat32_audio_streamer';AudioPlayer='tb_tf_pcm_audio_player'}
$markers=@{Control='PASS UART commands';Scale='ALL SCALE/LOAD TESTS PASSED';Ingest='PASS FAT root chain';Memory='PASS progressive loading';AudioStreamer='PASS audio FAT32';AudioPlayer='PASS PCM event selection'}
$tops['Overlay']='tb_terminal_overlay';$tops['MediaAssets']='tb_media_assets'
$tops['SectorArbiter']='tb_media_sector_arbiter'
$markers['Overlay']='PASS OSD glyph pixels';$markers['MediaAssets']='PASS actual six BMPs'
$markers['SectorArbiter']='PASS sector arbitration'
$tops['SectorReplay']='tb_sector_replay';$markers['SectorReplay']='PASS bounded sector retries'
$tops['LoadContention']='tb_load_contention';$markers['LoadContention']='PASS full-row background contention'
$cases['IngestRetry']=$cases['Ingest']
$tops['IngestRetry']='tb_fat_ingest';$markers['IngestRetry']='PASS whole-image retry'
$tops['Safety']='tb_terminal_safety';$markers['Safety']='PASS safety switch debounce'
$tops['Fallback']='tb_alarm_fallback';$markers['Fallback']='PASS TF-independent alarm'
$tops['SafetyOverlay']='tb_safety_overlay';$markers['SafetyOverlay']='PASS map pixels'
$tops['Plan']='tb_plan_config';$markers['Plan']='PASS configurable plan'
$tops['Recovery']='tb_media_recovery';$markers['Recovery']='PASS media self-healing'
$selected=if($Test -eq 'All'){@('Safety','Fallback','SafetyOverlay','Control','Plan','Recovery','Scale','Ingest','IngestRetry','Memory','AudioStreamer','AudioPlayer','Overlay','SectorArbiter','SectorReplay','LoadContention','MediaAssets')}else{@($Test)}
foreach($name in $selected){
 $compiled=Join-Path $out ($name+'.vvp')
 $log=Join-Path $out ($name+'.log')
 foreach($p in $cases[$name]){if(!(Test-Path -LiteralPath $p)){throw "Missing source: $p"}}
 Write-Host "Compile $name"
 $extra=@()
 if($name -eq 'IngestRetry'){$extra=@('-Ptb_fat_ingest.TEST_RETRY=1')}
 & $Iverilog -g2012 -s $tops[$name] -o $compiled @extra @($cases[$name])
 if($LASTEXITCODE -ne 0){throw "Compilation failed: $name"}
 Write-Host "Run $name (full pixel checks can take several minutes)"
 Push-Location $root
 try { & $Vvp -i $compiled | Tee-Object -FilePath $log } finally { Pop-Location }
 if($LASTEXITCODE -ne 0){throw "Simulation failed: $name"}
 $result=Get-Content -LiteralPath $log -Raw
 if(!$result.Contains($markers[$name])){throw "PASS marker missing: $name"}
}
Write-Host 'All requested simulations passed.'
if($Test -eq 'All'){Write-Output 'Full V2 regression completed: 17/17.'}
