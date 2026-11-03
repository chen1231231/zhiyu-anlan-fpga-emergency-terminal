`timescale 1ns/1ps
module tb_terminal_overlay;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [9:0] x=0,y=0;reg [2:0] b=0,c=0,v=2;
 reg [2:0] page=0;reg ready=1;reg [3:0] failure=0;
 reg [5:0] available=6'h3f;
 wire [23:0] rgb;integer xx,yy,start_x,msg,char_index,on_pixels=0,bar_pixels,level,preview;
 reg [15:0] expected_dots;
 terminal_overlay dut(.clk(clk),.rst_n(rst_n),.hs(1'b1),.vs(1'b1),.de(1'b1),.x(x),.y(y),
  .rgb(24'h808080),.page(page),.emergency(1'b0),.acknowledged(1'b0),.auto_enabled(1'b1),
  .image_ready(ready),.content_override(1'b0),.failure_reason(failure),.event_id(16'h0000),.brightness(b),.contrast(c),.volume_level(v),.reveal_step(5'd20),
  .available_mask(available),
  .hs_out(),.vs_out(),.de_out(),.x_out(),.rgb_out(rgb));
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(msg=19;msg<=21;msg=msg+1)begin
   start_x=msg==19?344:msg==20?416:488;
   for(yy=0;yy<16;yy=yy+1)for(xx=0;xx<(msg==20?48:32);xx=xx+1)begin
    @(negedge clk);x=start_x+xx;y=8+yy;#1;
    char_index=msg==20?dut.u_font.code:dut.u_font.code;
    expected_dots=dut.u_font.glyphs[{dut.u_font.code,yy[3:0]}];
    @(posedge clk);#1;
    if(rgb !== (expected_dots[15-(xx%16)]?24'hffffff:24'h0b182a))
     $fatal(1,"Chinese glyph mismatch msg=%0d x=%0d y=%0d",msg,xx,yy);
    if(rgb==24'hffffff)on_pixels=on_pixels+1;
   end
  end
  // Former 0000 region must remain background once outside the volume label.
  for(yy=8;yy<24;yy=yy+1)for(xx=520;xx<560;xx=xx+1)begin
   @(negedge clk);x=xx;y=yy;@(posedge clk);#1;
   if(rgb!=24'h0b182a)$fatal(1,"event ID still drawn at %0d,%0d",xx,yy);
  end
  for(level=0;level<5;level=level+1)begin
   b=level;c=level;v=level;bar_pixels=0;
   for(xx=344;xx<556;xx=xx+1)begin
    @(negedge clk);x=xx;y=30;@(posedge clk);#1;
    if(rgb==24'h5de3a4)bar_pixels=bar_pixels+1;
   end
   if(bar_pixels!=3*(5-level)*12)$fatal(1,"wrong five-level bars %0d: %0d",level,bar_pixels);
  end
  if(on_pixels<100)$fatal(1,"empty Chinese glyph ROM");
  for(msg=0;msg<6;msg=msg+1)begin
   page=msg;@(negedge clk);x=16;y=8;#1;
   if(dut.message!=6+msg)$fatal(1,"title is not tied to displayed page");
  end
  page=0;ready=0;
  for(msg=0;msg<=5;msg=msg+1)begin
   failure=msg;@(negedge clk);x=192;y=276;#1;
   if(dut.message!=(msg==0?16:21+msg))$fatal(1,"loading/failure status mismatch");
  end
  ready=1;failure=0;
  for(msg=0;msg<=6;msg=msg+1)begin
   available=(1<<msg)-1;
   @(negedge clk);x=592;y=8;#1;
   if(dut.message!=28 || dut.character!=msg+2)$fatal(1,"wrong ready image count");
  end
  // Render the actual RTL output, including font ROM latency, for visual QA.
  b=0;c=0;v=2;preview=$fopen("sim/results/osd_preview.ppm","w");
  $fdisplay(preview,"P3\n640 40\n255");
  for(yy=0;yy<40;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
   @(negedge clk);x=xx;y=yy;@(posedge clk);#1;
   $fdisplay(preview,"%0d %0d %0d",rgb[23:16],rgb[15:8],rgb[7:0]);
  end
  $fclose(preview);
  $display("PASS OSD glyph pixels, no 0000, five-level bars; lit glyph pixels=%0d",on_pixels);$finish;
 end
endmodule
