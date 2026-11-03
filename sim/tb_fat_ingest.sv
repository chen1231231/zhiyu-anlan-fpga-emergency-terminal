`timescale 1ns/1ps
module tb_fat_ingest #(parameter TEST_RETRY=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,sbusy=0,svalid=0,sdone=0;
 reg [7:0] sbyte=0;reg [8:0] sindex=0;
 reg [7:0] sector_error=0;
 integer safety_attempts=0;
 wire req,done,wr;wire [31:0] lba,data;wire [20:0] addr;
 wire [5:0] resources,complete;wire [2:0] image;wire [7:0] err,detail;
 reg [7:0] boot[0:511],root_a[0:511],root_b[0:511];
 integer i,k,offset,sector_count=0,writes=0;reg [31:0] request_lba;
 localparam DATA_START=1056,SPC=128,FILESIZE=230454;
 wire [5:0] failed;wire [23:0] failures;
 media_ingest_pipeline dut(.clk(clk),.rst_n(rst_n),.start(start),.done(done),.busy(),
 .image_failed(failed),.image_failure_codes(failures),
 .ingest_error(err),.ingest_detail_error(detail),.current_image(image),.resource_valid(resources),
 .image_complete(complete),.sector_req(req),.sector_lba(lba),.sector_busy(sbusy),
 .audio_file_start(1'b0),.audio_file_stop(1'b0),.audio_file_select(2'd0),.audio_sector_admit(1'b0),
 .sector_valid(svalid),.sector_byte(sbyte),.sector_byte_index(sindex),.sector_done(sdone),.sector_error(sector_error),
 .controller_init_done(1'b1),.controller_busy(1'b0),.refresh_active(1'b0),.burst_grant(1'b1),
 .burst_request(),.burst_busy(),.app_wr_en(wr),.app_wr_addr(addr),.app_wr_mask(),.app_wr_data(data));
 task entry(input integer slot,input [87:0] name,input integer cluster,sz,input second);
 integer q,b;begin b=slot*32;
 for(q=0;q<32;q=q+1)if(second)root_b[b+q]=0;else root_a[b+q]=0;
 for(q=0;q<11;q=q+1)if(second)root_b[b+q]=name[87-q*8-:8];else root_a[b+q]=name[87-q*8-:8];
 if(second)begin root_b[b+11]='h20;root_b[b+26]=cluster;for(q=0;q<4;q=q+1)root_b[b+28+q]=(sz>>(8*q));end
 else begin root_a[b+11]='h20;root_a[b+26]=cluster;for(q=0;q<4;q=q+1)root_a[b+28+q]=(sz>>(8*q));end
 end endtask
 function automatic [7:0] get_byte(input integer sec,idx);
 integer n,which,cluster,word,byteoff,nextc;reg [31:0] header;
 begin
 get_byte=0;
 if(sec==0)get_byte=boot[idx];
 else if(sec==DATA_START)get_byte=root_a[idx];
 else if(sec==DATA_START+SPC)get_byte=root_b[idx];
 else if(sec>DATA_START&&sec<DATA_START+SPC)get_byte=idx%32==0?8'he5:0;
 else if(sec>=32&&sec<1056)begin
  cluster=(sec-32)*128+idx/4;nextc='hfffffff;
  if(cluster==2)nextc=3;
  else if(cluster>=10&&cluster<=29&&cluster%4!=1)nextc=cluster+1;
  get_byte=nextc>>((idx%4)*8);
 end else if(sec>=DATA_START+8*SPC)begin
  n=(sec-(DATA_START+8*SPC))*512+idx;
  which=n/(4*SPC*512);byteoff=n%(4*SPC*512);
  // All valid files are bottom-up, 320x240, constant bank-dependent RGB.
  if(byteoff>=54)begin
   case((byteoff-54)%3)
    0:get_byte=8'h30+which;1:get_byte=8'h60+which;2:get_byte=8'h90+which;
   endcase
  end else begin
   header=0;
   case(byteoff/4)
    0:header=32'h4642|(FILESIZE<<16);
    1:header=FILESIZE>>16;
    2:header=0;
    3:header=40<<16|54;
    4:header=320<<16;
    5:header=240<<16;
    6:header=24<<16|1;
    7:header=0;
    8:header=(FILESIZE-54)<<16;
    9:header=(FILESIZE-54)>>16;
   endcase
   // Easier bytewise BMP fields below override the packed header.
   get_byte=0;
   case(byteoff)
    0:get_byte='h42;1:get_byte='h4d;
    2,3,4,5:get_byte=FILESIZE>>((byteoff-2)*8);
    10:get_byte=54;14:get_byte=40;18:get_byte=64;19:get_byte=1;
    22:get_byte=240;26:get_byte=1;28:get_byte=which==1?32:24;
    34,35,36,37:get_byte=(FILESIZE-54)>>((byteoff-34)*8);
   endcase
  end
 end
 end endfunction
 // Real sector pacing, including separate done after the final byte.
 initial forever begin
  wait(req);@(negedge clk);request_lba=lba;sbusy=1;sector_count=sector_count+1;
  sector_error=0;
  if(request_lba==DATA_START+24*SPC) safety_attempts=safety_attempts+1;
  if(TEST_RETRY && request_lba==DATA_START+24*SPC && safety_attempts==1) begin
   // Exhausted low-level retries on the first SAFETY sector. The pipeline
   // must drain the failed image, restart it once and continue later banks.
   repeat(8) @(negedge clk);
   sector_error=8'h03;
  end else begin
  if(sector_count>127&&sector_count<134)$display("request %d lba=%d byte8=%h",sector_count,request_lba,get_byte(request_lba,8));
  for(k=0;k<512;k=k+1)begin
   sindex=k;sbyte=get_byte(request_lba,k);svalid=1;@(negedge clk);svalid=0;
   repeat(15)@(negedge clk);
  end
  end
  sdone=1;@(negedge clk);sdone=0;sbusy=0;
 end
 always @(posedge clk)if(wr)begin
  writes=writes+1;
  if(addr/307200!=0&&addr/307200!=1&&addr/307200!=4)$fatal(1,"bad bank committed/write %d",addr/307200);
 end
 always @(posedge clk)if(dut.u_volume_scanner.state==14)
  $display("root FAT parse cluster=%d next=%h max=%d lba=%d",dut.u_volume_scanner.root_cluster,dut.u_volume_scanner.root_next,dut.u_volume_scanner.max_cluster,lba);
 initial begin
  for(i=0;i<512;i=i+1)begin boot[i]=0;root_a[i]=0;root_b[i]=0;end
  boot[0]='heb;boot[11]=0;boot[12]=2;boot[13]=128;boot[14]=32;boot[16]=1;
  boot[34]='h10;boot[37]=4;boot[44]=2;boot[510]='h55;boot[511]='haa;
  // First root cluster is full; second contains an end marker and shuffled files.
  for(i=0;i<16;i=i+1)root_a[i*32]='he5;
  entry(1,"FIRE    BMP",14,60,0);entry(15,"NORMAL  BMP",10,FILESIZE,0);
  entry(0,"EVAC    BMP",22,60,1);entry(1,"SAFETY  BMP",26,FILESIZE,1);
  entry(2,"FLOOD   BMP",18,FILESIZE,1); // QUAKE deliberately absent
  repeat(5)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(failed!=6'b101100 || failures[3*4 +:4]!=1 || failures[2*4 +:4]!=3 || failures[5*4 +:4]!=3)
   $fatal(1,"wrong permanent failure status failed=%b reasons=%h",failed,failures);
  if(resources!='b110111||complete!='b010011||writes!=3*307200)
   $fatal(1,"resources=%b complete=%b writes=%d err=%h detail=%h",resources,complete,writes,err,detail);
  if(TEST_RETRY && safety_attempts!=2) $fatal(1,"SAFETY retry count %0d",safety_attempts);
  if(TEST_RETRY) $display("PASS whole-image retry: second page recovered after sector failure, later valid banks committed");
  $display("PASS FAT root chain + shuffled names + missing/corrupt/truncated files; later valid banks loaded; %0d sectors %0d writes",sector_count,writes);
  $finish;
 end
 initial begin #300000000;$fatal(1,"ingest timeout state=%d image=%d load=%d decoder_error=%h",dut.state,image,dut.u_frame_loader.active,dut.bmp_error);end
endmodule
