`timescale 1ns/1ps
// Actual release files on a synthetic FAT32 volume. Only the physical SD
// service is replaced; storage start/init, replay, scanning, both FAT readers,
// BMP decoding, frame writes and the real audio FIFO/player all run together.
module tb_media_assets;
 reg clk=0,pclk=0; always #12.5 clk=~clk; always #20 pclk=~pclk;
 reg rst_n=0,start=0,alarm=0; reg [1:0] event_type=0; reg [7:0] volume=128;
 wire done,wr,ready,fs,stop,admit,fb,fd,fv,sv;
 wire [1:0] select_file; wire [3:0] audios; wire [5:0] resources,complete;
 wire [5:0] image_crc_ok,image_crc_failed;wire [3:0] audio_crc_ok,audio_crc_failed;
 wire plan_valid; wire plan_error; wire [29:0] plan_data;
 wire [31:0] data; wire [20:0] addr; wire [7:0] fbyte,ferr,perr,err,detail;
 wire signed [15:0] sample; wire underflow;
 media_storage_ingest_top #(.VERIFY_RELEASE_CRC(1)) dut(.clk(clk),.rst_n(rst_n),.start(start),.busy(),.done(done),
  .error_stage(),.error_code(err),.error_detail(detail),.card_ready(ready),.card_high_capacity(),
  .resource_valid(resources),.image_complete(complete),.audio_resource_valid(audios),
  .image_crc_ok(image_crc_ok),.image_crc_failed(image_crc_failed),.audio_crc_ok(audio_crc_ok),.audio_crc_failed(audio_crc_failed),
  .plan_valid(plan_valid),.plan_error(plan_error),.plan_data(plan_data),
  .audio_file_start(fs),.audio_file_stop(stop),.audio_file_select(select_file),.audio_sector_admit(admit),
  .audio_file_busy(fb),.audio_file_done(fd),.audio_file_valid(fv),.audio_file_byte(fbyte),.audio_file_error(ferr),
  .controller_init_done(1'b1),.controller_busy(1'b0),.refresh_active(1'b0),.burst_grant(1'b1),
  .burst_request(),.burst_busy(),.app_wr_en(wr),.app_wr_addr(addr),.app_wr_mask(),.app_wr_data(data),
  .sd_cs_n(),.sd_sclk(),.sd_mosi(),.sd_miso(1'b1));
 tf_pcm_audio_player player(.mem_clk(clk),.mem_rst_n(rst_n),.pix_clk(pclk),.pix_rst_n(rst_n),
  .alarm_enable(alarm),.audio_test(1'b0),.event_type(event_type),.volume(volume),.audio_available(audios),
  .file_start(fs),.file_stop(stop),.file_select(select_file),.sector_admit(admit),.file_busy(fb),
  .file_done(fd),.file_valid(fv),.file_byte(fbyte),.file_error(ferr),
  .sample_valid(sv),.sample_left(sample),.sample_right(),.underflow(underflow),.player_error(perr));
 integer counts[0:5], i,bank,pos,offset,audio_offset=0,audio_bytes=0;
 integer source_x,source_y,source_row,capture[0:1];
 reg seen[0:1843199];reg [23:0] captured_pixels[0:614399];
 integer q;reg [7:0] crc_check;
 integer samples[0:3], starts=0; reg [1:0] previous_select;
 reg saw_background_audio=0; reg [5:0] prior_complete=0;
 always @(posedge clk) if(rst_n) begin
  if(wr) begin
   bank=addr/307200;pos=addr%307200;
   if(bank>5)$fatal(1,"write out of six banks");
   // Independent reference: map each normalized coordinate back into the
   // actual file dimensions, including bottom-up/top-down row orientation.
   source_x=(pos%640)*dut.u_sd_service.image_widths[bank]/640;
   source_y=dut.u_sd_service.image_top_down[bank] ? pos/640:479-pos/640;
   source_row=source_y*dut.u_sd_service.image_heights[bank]/480;
   offset=bank*dut.u_sd_service.IMAGE_BYTES+dut.u_sd_service.image_offsets[bank]+
          (source_row*dut.u_sd_service.image_widths[bank]+source_x)*3;
   if(data !== {8'd0,dut.u_sd_service.images[offset+2],dut.u_sd_service.images[offset+1],dut.u_sd_service.images[offset]})
    $fatal(1,"release image mismatch bank=%0d pos=%0d data=%h",bank,pos,data);
   if(seen[addr])$fatal(1,"repeated normalized address bank=%0d pos=%0d",bank,pos);
   seen[addr]=1;
   if(bank<2)captured_pixels[addr]=data[23:0];
   counts[bank]=counts[bank]+1;
  end
  if(complete!=prior_complete) begin
   $display("release banks committed: %b at %0t",complete,$time);prior_complete=complete;
  end
  if(fs)begin audio_offset=0;previous_select=select_file;starts=starts+1;end
  if(fv && !stop)begin
   if(fbyte!==dut.u_sd_service.audio[previous_select*262144+audio_offset])
    $fatal(1,"audio byte mismatch file=%0d offset=%0d",previous_select,audio_offset);
   audio_offset=audio_offset+1;audio_bytes=audio_bytes+1;
   if(complete!=63)saw_background_audio=1;
  end
  if(ferr!=0||perr!=0)$fatal(1,"audio errors %h %h",ferr,perr);
 end
 always @(posedge pclk) if(rst_n && sv && sample!=0 && alarm) samples[event_type]=samples[event_type]+1;
 task play_event(input [1:0] typ);
  integer before_samples;
  begin
   @(negedge pclk);event_type=typ;alarm=1;before_samples=samples[typ];
   wait(samples[typ]>=before_samples+128);
   // Changing gain to zero must silence the emitted HDMI samples.
   @(negedge pclk);volume=0;repeat(2000)@(negedge pclk);
   if(sample!=0)$fatal(1,"volume zero did not mute");
   volume=128;
   @(negedge pclk);alarm=0;repeat(1000)@(negedge clk);
  end
 endtask
 initial begin
  capture[0]=$fopen("sim/results/scale_normal.ppm","wb");
  capture[1]=$fopen("sim/results/scale_safety.ppm","wb");
  if(!capture[0]||!capture[1])$fatal(1,"cannot create normalized pixel captures");
  for(i=0;i<2;i=i+1)$fwrite(capture[i],"P6\n640 480\n255\n");
  for(i=0;i<1843200;i=i+1)seen[i]=0;
  for(i=0;i<6;i=i+1)counts[i]=0;
  for(i=0;i<4;i=i+1)samples[i]=0;
  repeat(8)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
  wait(audios==15);
  play_event(0);play_event(1);play_event(2);play_event(3);
  wait(done);@(negedge clk);
  if(err!=0||detail!=0||resources!=63||complete!=63||image_crc_ok!=63||image_crc_failed!=0)
   $fatal(1,"ingest/CRC error=%h/%h resources=%b complete=%b crc=%b/%b",err,detail,resources,complete,image_crc_ok,image_crc_failed);
  if(!plan_valid||plan_error||plan_data[4:0]!=5||plan_data[8:5]!=2||
     plan_data[11:9]!=2||plan_data[21:14]!=8'haa||plan_data[29:22]!=8'h39)
   $fatal(1,"PLAN.BIN decode mismatch valid=%b error=%h data=%h",plan_valid,plan_error,plan_data);
  for(i=0;i<6;i=i+1)if(counts[i]!=307200)$fatal(1,"bank %0d wrote %0d pixels",i,counts[i]);
  for(i=0;i<4;i=i+1)begin
   crc_check=0;
   for(q=0;q<dut.u_sd_service.sizes[i];q=q+1)
    crc_check=dut.u_ingest_frontend.u_ingest_pipeline.crc8_byte(
        crc_check,dut.u_sd_service.audio[i*262144+q]);
   if(crc_check!==dut.u_ingest_frontend.u_ingest_pipeline.expected_audio_crc(i[1:0]))
    $fatal(1,"audio CRC constant mismatch file=%0d crc=%h",i,crc_check);
  end
  if(!saw_background_audio||audio_bytes<1024||starts<4)$fatal(1,"joint audio coverage missing");
  // Recovery must rescan metadata without touching any verified SDRAM bank.
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(err!=0||complete!=63||image_crc_ok!=63||!plan_valid||plan_error)
   $fatal(1,"verified-frame rescan failed err=%h complete=%b crc=%b",err,complete,image_crc_ok);
  for(i=0;i<6;i=i+1)if(counts[i]!=307200)$fatal(1,"recovery overwrote visible bank %0d",i);
  // A checksum-correct but nonzero reserved byte must still be rejected.
  dut.u_sd_service.plan[12]=1;
  dut.u_sd_service.plan[23]=dut.u_sd_service.plan[23]^1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(plan_valid||!plan_error)$fatal(1,"reserved PLAN byte accepted");
  dut.u_sd_service.plan[12]=0;
  dut.u_sd_service.plan[23]=dut.u_sd_service.plan[23]^1;
  // Optional missing plan selects defaults while cached images stay intact.
  dut.u_sd_service.directory[10*32]=0;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(plan_valid||plan_error||plan_data!=0||err!=0)$fatal(1,"missing PLAN did not fall back");
  for(i=0;i<6;i=i+1)if(counts[i]!=307200)$fatal(1,"fallback rescan overwrote bank %0d",i);
  for(i=0;i<614400;i=i+1)$fwrite(capture[i/307200],"%c%c%c",
   captured_pixels[i][23:16],captured_pixels[i][15:8],captured_pixels[i][7:0]);
  for(i=0;i<2;i=i+1)$fclose(capture[i]);
  $display("PASS mixed-size actual assets: 320x240 enlarged, 800x600 reduced, four 640x480 unchanged; normalized pixels and addresses checked");
  $display("PASS actual six BMPs: 1843200 matching SDRAM writes; four PCM streams, background sound, volume mute; valid PLAN.BIN; starts=%0d bytes=%0d",starts,audio_bytes);
  $finish;
 end
 initial begin #4000000000;$fatal(1,"media timeout complete=%b state=%d image=%d error=%h/%h",complete,dut.u_ingest_frontend.u_ingest_pipeline.state,dut.u_ingest_frontend.u_ingest_pipeline.current_image,err,detail);end
endmodule

module sd_media_service #(parameter SPI_CLK_DIV=4)(
 input clk,rst_n,init_start, input sector_req,input [31:0] sector_lba,
 output reg init_done=0,init_ready=0,output init_busy,output [7:0] init_error,
 output card_high_capacity,output [31:0] card_ocr,output owner_reader,
 output reg sector_busy=0,sector_done=0,sector_valid=0,
 output reg [7:0] sector_byte=0,output reg [8:0] sector_byte_index=0,
 output [7:0] sector_error,output sd_cs_n,sd_sclk,sd_mosi,input sd_miso
);
 localparam IMAGE_BYTES=1440054,IMAGE_CLUSTERS=24,IMAGE_START=10,
            AUDIO_START=IMAGE_START+6*IMAGE_CLUSTERS,PLAN_START=AUDIO_START+16,
            DATA_START=1056,SPC=128;
 reg [7:0] images[0:6*IMAGE_BYTES-1],audio[0:4*262144-1],boot[0:511],directory[0:511],plan[0:23];
 integer image_sizes[0:5],image_widths[0:5],image_heights[0:5],image_offsets[0:5];
 reg image_top_down[0:5];
 integer sizes[0:3];integer i,j,f,n,k,request_lba;
 assign init_busy=0;assign init_error=0;assign card_high_capacity=1;assign card_ocr=0;assign owner_reader=1;
 assign sector_error=0;assign sd_cs_n=1;assign sd_sclk=0;assign sd_mosi=0;
 function automatic integer image_le32(input integer bank,at);
  integer q;begin image_le32=0;
   for(q=0;q<4;q=q+1)image_le32=image_le32|(integer'(images[bank*IMAGE_BYTES+at+q])<<(8*q));
  end
 endfunction
 task load_image(input integer bank,input [255:0] name);
 begin f=$fopen(name,"rb");if(!f)$fatal(1,"missing release image %s",name);
 n=$fread(images,f,bank*IMAGE_BYTES,IMAGE_BYTES);$fclose(f);
 image_sizes[bank]=n;image_widths[bank]=image_le32(bank,18);
 image_heights[bank]=image_le32(bank,22);image_top_down[bank]=image_heights[bank]<0;
 if(image_top_down[bank])image_heights[bank]=-image_heights[bank];
 image_offsets[bank]=image_le32(bank,10);
 if(n!=image_offsets[bank]+image_widths[bank]*image_heights[bank]*3)
  $fatal(1,"bad release image size bank=%0d bytes=%0d",bank,n);
 if((bank==0&&(image_widths[bank]!=320||image_heights[bank]!=240))||
    (bank==1&&(image_widths[bank]!=800||image_heights[bank]!=600))||
    (bank>=2&&(image_widths[bank]!=640||image_heights[bank]!=480)))
  $fatal(1,"wrong mixed-size release dimensions bank=%0d",bank);
 $display("actual BMP bank=%0d size=%0dx%0d bytes=%0d",bank,image_widths[bank],image_heights[bank],n);
 end endtask
 task load_audio(input integer file_index,input [255:0] name);
 begin f=$fopen(name,"rb");if(!f)$fatal(1,"missing release PCM %s",name);
 sizes[file_index]=$fread(audio,f,file_index*262144,262144);$fclose(f);
 if(sizes[file_index]<256)$fatal(1,"PCM too short");end endtask
 task entry(input integer slot,input [87:0] name,input integer cluster,sz);
 integer q,b;begin b=slot*32;for(q=0;q<11;q=q+1)directory[b+q]=name[87-q*8-:8];
 directory[b+11]='h20;directory[b+26]=cluster;directory[b+27]=cluster>>8;
 for(q=0;q<4;q=q+1)directory[b+28+q]=sz>>(8*q);end endtask
 initial begin
  for(i=0;i<512;i=i+1)begin boot[i]=0;directory[i]=0;end
  load_image(0,"TF_CARD_ROOT/NORMAL.BMP");load_image(1,"TF_CARD_ROOT/SAFETY.BMP");
  load_image(2,"TF_CARD_ROOT/FIRE.BMP");load_image(3,"TF_CARD_ROOT/QUAKE.BMP");
  load_image(4,"TF_CARD_ROOT/FLOOD.BMP");load_image(5,"TF_CARD_ROOT/EVAC.BMP");
  load_audio(0,"TF_CARD_ROOT/ALARM.PCM");load_audio(1,"TF_CARD_ROOT/FIRE.PCM");
  load_audio(2,"TF_CARD_ROOT/QUAKE.PCM");load_audio(3,"TF_CARD_ROOT/FLOOD.PCM");
  boot[0]='heb;boot[12]=2;boot[13]=SPC;boot[14]=32;boot[16]=1;
  boot[34]='h10;boot[37]=4;boot[44]=2;boot[510]='h55;boot[511]='haa;
  entry(0,"NORMAL  BMP",IMAGE_START,image_sizes[0]);
  entry(1,"SAFETY  BMP",IMAGE_START+IMAGE_CLUSTERS,image_sizes[1]);
  entry(2,"FIRE    BMP",IMAGE_START+2*IMAGE_CLUSTERS,image_sizes[2]);
  entry(3,"QUAKE   BMP",IMAGE_START+3*IMAGE_CLUSTERS,image_sizes[3]);
  entry(4,"FLOOD   BMP",IMAGE_START+4*IMAGE_CLUSTERS,image_sizes[4]);
  entry(5,"EVAC    BMP",IMAGE_START+5*IMAGE_CLUSTERS,image_sizes[5]);
  // PCM entries deliberately come AFTER all six BMPs, catching early exit.
  entry(6,"ALARM   PCM",AUDIO_START,sizes[0]);entry(7,"FIRE    PCM",AUDIO_START+4,sizes[1]);
  entry(8,"QUAKE   PCM",AUDIO_START+8,sizes[2]);entry(9,"FLOOD   PCM",AUDIO_START+12,sizes[3]);
  entry(10,"PLAN    BIN",PLAN_START,24);
  plan[0]="E";plan[1]="P";plan[2]="L";plan[3]="N";plan[4]=1;plan[5]=1;
  plan[6]=5;plan[7]=2;plan[8]=2;plan[9]=0;plan[10]=8'haa;plan[11]=8'h39;
  for(i=12;i<23;i=i+1)plan[i]=0;
  plan[23]=0;for(i=0;i<23;i=i+1)plan[23]=plan[23]^plan[i];
 end
 function automatic [7:0] get_byte(input integer sec,idx);
 integer cluster,bank,off,nextc;
 begin get_byte=0;
  if(sec==0)get_byte=boot[idx];
  else if(sec==DATA_START)get_byte=directory[idx];
  else if(sec>=32&&sec<DATA_START)begin
   cluster=(sec-32)*128+idx/4;nextc='hfffffff;
   if(cluster>=IMAGE_START&&cluster<AUDIO_START)begin
    bank=(cluster-IMAGE_START)/IMAGE_CLUSTERS;
    off=(cluster-IMAGE_START)%IMAGE_CLUSTERS;
    if((off+1)*SPC*512<image_sizes[bank])nextc=cluster+1;
   end else if(cluster>=AUDIO_START&&cluster<PLAN_START && ((cluster-AUDIO_START)%4)<3)nextc=cluster+1;
   get_byte=nextc>>((idx%4)*8);
  end else if(sec>=DATA_START+(PLAN_START-2)*SPC&&sec<DATA_START+(PLAN_START-1)*SPC)begin
   off=(sec-DATA_START-(PLAN_START-2)*SPC)*512+idx;if(off<24)get_byte=plan[off];
  end else if(sec>=DATA_START+(IMAGE_START-2)*SPC&&sec<DATA_START+(AUDIO_START-2)*SPC)begin
   bank=(sec-DATA_START-(IMAGE_START-2)*SPC)/(IMAGE_CLUSTERS*SPC);
   off=((sec-DATA_START-(IMAGE_START-2)*SPC)%(IMAGE_CLUSTERS*SPC))*512+idx;
   if(off<image_sizes[bank])get_byte=images[bank*IMAGE_BYTES+off];
  end else if(sec>=DATA_START+(AUDIO_START-2)*SPC)begin
   bank=(sec-DATA_START-(AUDIO_START-2)*SPC)/(4*SPC);off=((sec-DATA_START-(AUDIO_START-2)*SPC)%(4*SPC))*512+idx;
   if(bank<4&&off<sizes[bank])get_byte=audio[bank*262144+off];
  end
 end endfunction
 always @(posedge clk) begin init_done<=0;if(init_start)begin init_ready<=1;init_done<=1;end end
 initial forever begin
  wait(sector_req);@(negedge clk);request_lba=sector_lba;sector_busy=1;
  for(k=0;k<512;k=k+1)begin
   sector_byte_index=k;sector_byte=get_byte(request_lba,k);sector_valid=1;@(negedge clk);
  end
  sector_valid=0;sector_done=1;@(negedge clk);sector_done=0;sector_busy=0;
 end
endmodule
