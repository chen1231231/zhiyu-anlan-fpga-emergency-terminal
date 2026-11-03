`timescale 1ns/1ps
module tb_safety_overlay;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,en=1,frame=0;reg [9:0] x=0,y=0;reg [1:0] view=1,zone=0,exits=2;
 reg emergency=1,acknowledged=0,auto_enabled=1;reg [1:0] event_type=0;
 reg [1:0] scene_mode=0;reg pending_confirm=0,clear_pending=0;
 reg [1:0] alert_level=2;reg route_pending=0,drill_report=0;
 reg [3:0] drill_route_changes=1;reg drill_corrected=0;
 reg [3:0] hazards=1;
 wire [1:0] recommended_exit=exits==0 ? 0:exits[0] ? 1:2;
 reg audio_active=1,pcm_valid=0;reg signed [15:0] pcm_sample=0;
 wire [23:0] rgb;wire draw;
 wire [23:0] header_rgb;
 reg image_background=0;
 reg [7:0] bitmap[0:921653];
 integer image_offset,bitmap_file,bitmap_bytes,m;
 wire [23:0] image_rgb=image_background ?
     {bitmap[image_offset+2],bitmap[image_offset+1],bitmap[image_offset]}:24'h123f68;
 always @* image_offset=54+((479-y)*640+x)*3;
 wire [23:0] composed_rgb=draw ? rgb:header_rgb;
 terminal_overlay header(.clk(clk),.rst_n(rst_n),.hs(1'b1),.vs(!frame),.de(1'b1),
 .x(x),.y(y),.rgb(image_rgb),.page(emergency ? {1'b0,event_type}+3'd2:3'd0),
 .emergency(emergency),.acknowledged(acknowledged),.auto_enabled(auto_enabled),.image_ready(1'b1),
 .content_override(en),.failure_reason(4'd0),.available_mask(6'h3f),.event_id(16'd1),
 .brightness(3'd0),.contrast(3'd0),.volume_level(3'd2),.reveal_step(5'd20),
 .hs_out(),.vs_out(),.de_out(),.x_out(),.rgb_out(header_rgb));
 integer xx,yy,n,f,arrows,red_zones,access_pixels,status_pixels;
 terminal_safety_overlay dut(.clk(clk),.rst_n(rst_n),.frame_start(frame),.enabled(en),
 .x(x),.y(y),.view(view),.zone(zone),.exits_open(exits),.elapsed(10'd123),
 .hazard_mask(hazards),.audio_active(audio_active),.pcm_valid(pcm_valid),.pcm_sample(pcm_sample),
 .history_scene(8'h00),
 .history({{2'd2,1'b1,2'd3,2'd3,10'd10},{2'd1,1'b0,2'd2,2'd2,10'd8},
           {2'd0,1'b0,2'd1,2'd1,10'd4},{2'd0,1'b0,2'd0,2'd0,10'd3}}),.history_count(3'd4),
 .emergency(emergency),.acknowledged(acknowledged),.auto_enabled(auto_enabled),.event_type(event_type),
 .scene_mode(scene_mode),.pending_confirm(pending_confirm),.clear_pending(clear_pending),
  .alert_level(alert_level),.route_pending(route_pending),.recommended_exit(recommended_exit),.route_score(exits==0?7'd0:(hazards==5||hazards==10)?7'd70:7'd95),
  .drill_report(drill_report),.drill_score(7'd92),.drill_confirm_seconds(8'd3),
  .drill_ack_seconds(10'd6),.drill_total_seconds(10'd42),.drill_route_changes(drill_route_changes),.drill_corrected(drill_corrected),
 .available(6'h3f),.audio_available(4'hf),.card_ok(1'b1),.memory_ok(1'b1),
  .audio_verified(1'b1),.asset_failed(1'b0),
 .clock_ok(1'b1),.fallback_active(1'b0),.rgb_out(rgb),.draw(draw));
 task pixel(input integer a,b);begin @(negedge clk);x=a;y=b;@(posedge clk);#1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
   pixel(552,8);if(!draw||rgb!==24'he96a19||dut.message!=95)$fatal(1,"labeled orange warning level badge missing");
   pixel(616,8);if(dut.message!=25||dut.character!=2)$fatal(1,"warning level number missing");
   for(yy=8;yy<24;yy=yy+1)for(xx=632;xx<640;xx=xx+1)begin
    pixel(xx,yy);if(!draw||rgb!==24'he96a19)$fatal(1,"legacy white /6 leaked past badge");
   end
  pixel(100,150);if(!draw||rgb!==24'h9c2338)$fatal(1,"hazard A missing");
  pixel(400,150);if(rgb!==24'h203b53)$fatal(1,"safe zone marked hazardous");
  for(n=0;n<4;n=n+1)begin
   zone=n;hazards=1<<n;exits=(n&1)?1:2;arrows=0;
   for(yy=236;yy<252;yy=yy+1)for(xx=80;xx<560;xx=xx+1)begin
    pixel(xx,yy);
    if(rgb==24'h37efad)begin
     arrows=arrows+1;
     if((xx<320 && !exits[0])||(xx>=320 && !exits[1]))$fatal(1,"arrow points to closed exit");
    end
   end
   if(arrows<100)$fatal(1,"no route arrows");
  end
  exits=0;hazards=15;
  for(yy=236;yy<252;yy=yy+1)for(xx=80;xx<560;xx=xx+1)begin
   pixel(xx,yy);if(rgb==24'h37efad)$fatal(1,"both closed still has safe arrow");
  end
  red_zones=0;
  pixel(100,150);if(rgb==24'h9c2338)red_zones=red_zones+1;
  pixel(400,150);if(rgb==24'h9c2338)red_zones=red_zones+1;
  pixel(100,300);if(rgb==24'h9c2338)red_zones=red_zones+1;
  pixel(400,300);if(rgb==24'h9c2338)red_zones=red_zones+1;
  if(red_zones!=4)$fatal(1,"SW3/all-exits-closed must mark all four zones hazardous");
  hazards=5;exits=2;
  pixel(100,150);if(rgb!=24'h9c2338)$fatal(1,"west A missing");
  pixel(100,300);if(rgb!=24'h9c2338)$fatal(1,"west C missing");
  pixel(400,150);if(rgb!=24'h203b53)$fatal(1,"west selection colored east B");
  pixel(400,300);if(rgb!=24'h203b53)$fatal(1,"west selection colored east D");
  pixel(192,104);if(dut.message!=97)$fatal(1,"west scope label");
  hazards=10;exits=1;
  pixel(400,150);if(rgb!=24'h9c2338)$fatal(1,"east B missing");
  pixel(400,300);if(rgb!=24'h9c2338)$fatal(1,"east D missing");
  pixel(100,150);if(rgb!=24'h203b53)$fatal(1,"east selection colored west A");
  pixel(192,104);if(dut.message!=98)$fatal(1,"east scope label");
  hazards=15;exits=0;
  repeat(16)begin @(negedge clk);frame=1;@(negedge clk);frame=0;end
  pixel(100,150);if(rgb!=24'hff4858)$fatal(1,"all-zone hazard did not flash bright");
  pixel(400,300);if(rgb!=24'hff4858)$fatal(1,"all-zone flash did not cover every zone");
  access_pixels=0;
  for(yy=416;yy<432;yy=yy+1)for(xx=32;xx<608;xx=xx+1)begin
   pixel(xx,yy);if(rgb==24'hffd166)access_pixels=access_pixels+1;
  end
  if(access_pixels<40)$fatal(1,"accessible emergency prompt missing");
  view=2;status_pixels=0;
  for(yy=304;yy<320;yy=yy+1)for(xx=80;xx<528;xx=xx+1)begin
   pixel(xx,yy);if(rgb==24'hffffff)status_pixels=status_pixels+1;
  end
  if(status_pixels<30)$fatal(1,"current event/status/time summary missing");
   pixel(100,210);if(dut.message!=13)$fatal(1,"image CRC status label missing");
   pixel(100,242);if(dut.message!=14)$fatal(1,"audio CRC status label missing");
  acknowledged=1;pixel(1,60);if(!draw||rgb!=24'hff4858)$fatal(1,"muting removed visual alarm");
  pixel(20,450);if(!draw)$fatal(1,"emergency ticker missing");
  repeat(16)begin @(negedge clk);frame=1;@(negedge clk);frame=0;end
  pixel(20,460);if(dut.message!=56)$fatal(1,"simultaneous English blocked-exit prompt missing");
  acknowledged=0;
  for(n=0;n<3;n=n+1)begin
   scene_mode=n;pixel(20,28);
   if(!draw||dut.message!=(n==2?53:n==1?54:52))$fatal(1,"scene label");
   pixel(200,28);if(dut.message!=69)$fatal(1,"scene auto/manual label");
   auto_enabled=0;pixel(200,28);if(dut.message!=70)$fatal(1,"manual label missing");auto_enabled=1;
   view=1;pixel(180,60);
   if(dut.message!=(n==2?38:n==1?37:32))$fatal(1,"map scene heading");
  end
  // Safety labels must leave the original five-segment controls visible.
  for(n=0;n<5;n=n+1)begin
   pixel(345+14*n,28);if(draw||composed_rgb!=24'h5de3a4)$fatal(1,"brightness bar obscured");
   pixel(417+14*n,28);if(draw||composed_rgb!=24'h5de3a4)$fatal(1,"contrast bar obscured");
   pixel(489+14*n,28);if(draw||(n<3 && composed_rgb!=24'h5de3a4))$fatal(1,"volume bar obscured");
  end
  view=1;exits=0;pixel(48,244);if(rgb!=24'hffffff)$fatal(1,"closed west exit has no X");
  pixel(592,244);if(rgb!=24'hffffff)$fatal(1,"closed east exit has no X");
  exits=1;pixel(20,460);if(dut.message!=71)$fatal(1,"English west exit mismatch");
  exits=2;pixel(20,460);if(dut.message!=72)$fatal(1,"English east exit mismatch");
  scene_mode=2;view=0;
  for(n=0;n<4;n=n+1)begin
   event_type=n;pixel(260,220);
   if(!draw||dut.message!=39+n)$fatal(1,"mall event card mismatch");
   pixel(n==0?180:148,276);if(dut.message!=44+2*n)$fatal(1,"centered mall instruction mismatch");
   pixel(n==0?242:n==1?234:n==2?218:202,356);if(dut.message!=62+n)$fatal(1,"mall English event label missing");
  end
  pending_confirm=1;pixel(260,220);if(dut.message!=34)$fatal(1,"publish confirmation Chinese text");
  pixel(202,276);if(dut.message!=58)$fatal(1,"publish confirmation English text");
  pixel(320,120);if(rgb!=24'hffd166)$fatal(1,"publish warning symbol missing");
  pending_confirm=0;clear_pending=1;
  pixel(260,220);if(dut.message!=35)$fatal(1,"clear confirmation Chinese text");
  pixel(218,276);if(dut.message!=59)$fatal(1,"clear confirmation English text");
  pixel(210,348);if(dut.message!=75)$fatal(1,"clear confirmation Chinese guidance");
  pixel(140,404);if(dut.message!=77)$fatal(1,"clear confirmation flow missing");
  pixel(282,150);if(rgb!=24'hff4858)$fatal(1,"clear symbol missing");
  clear_pending=0;scene_mode=0;event_type=0;
  // Real PCM peaks must animate every content page, remain inside blank areas,
  // and stop on mute or silence. The map and confirmation pages are excluded.
  view=0;pcm_sample=16'sh7fff;pcm_valid=1;repeat(3200)@(negedge clk);
  frame=1;@(negedge clk);frame=0;pcm_valid=0;
  for(n=0;n<3;n=n+1)begin
   scene_mode=n;
   for(f=0;f<4;f=f+1)begin
    event_type=f;
    pixel(69,n==2?79:379);
    if(!draw||rgb!=24'h00ff7f)$fatal(1,"cyan-green PCM center missing scene%0d event%0d",n,f);
    pixel(565,n==2?80:380);
    if(!draw||rgb!=24'h00ff7f)$fatal(1,"512px PCM strip right end missing");
    pixel(69,n==2?64:364);
    if(!draw||rgb!=24'hfff007)$fatal(1,"yellow upper crest missing");
    pixel(69,n==2?95:395);
    if(!draw||rgb!=24'hfff007)$fatal(1,"yellow lower crest missing");
    for(yy=0;yy<32;yy=yy+1)begin
     pixel(69,(n==2?64:364)+yy);
     if(!draw||!dut.audio_pixel)$fatal(1,"vertical stroke interrupted");
    end
    pixel(380,276);if(dut.audio_panel)$fatal(1,"audio obscures instruction text");
   end
  end
  // Full-scale bars are two pixels wide with a two-pixel transparent gap.
  en=0;scene_mode=0;
  for(xx=64;xx<576;xx=xx+1)begin
   pixel(xx,380);
   if((xx-64)%4<2)begin
    if(!draw||!dut.audio_pixel)$fatal(1,"spaced PCM stroke missing");
   end else if(draw||dut.audio_pixel)$fatal(1,"PCM stroke gap is not transparent");
  end
  pixel(68,380);if(rgb!=24'h00ff7f)$fatal(1,"first spaced column color wrong");
  pixel(69,380);if(rgb!=24'h00ff7f)$fatal(1,"second spaced column color wrong");
  pixel(63,382);if(draw)$fatal(1,"PCM strip extends left of 512px bounds");
  pixel(576,382);if(draw)$fatal(1,"PCM strip extends right of 512px bounds");
  acknowledged=1;
  for(yy=364;yy<396;yy=yy+1)for(xx=64;xx<576;xx=xx+1)begin
   pixel(xx,yy);if(draw||dut.audio_pixel||dut.text_on)$fatal(1,"muted strip has background or label");
  end
  acknowledged=0;pcm_valid=1;pcm_sample=0;repeat(3200)@(negedge clk);
  frame=1;@(negedge clk);frame=0;pcm_valid=0;
  pixel(69,380);if(draw)$fatal(1,"silent PCM still animates or has a panel");
  pcm_valid=1;pcm_sample=-16'sh8000;repeat(3200)@(negedge clk);
  frame=1;@(negedge clk);frame=0;pcm_valid=0;
  pixel(69,380);if(!draw||rgb!=24'h00ff7f)$fatal(1,"negative full scale PCM missing");
  audio_active=0;pixel(69,380);if(draw)$fatal(1,"inactive audio still drawn");audio_active=1;
  pending_confirm=1;pixel(66,382);if(dut.audio_panel)$fatal(1,"audio covers confirmation");pending_confirm=0;
  en=1;
  scene_mode=0;event_type=0;
   route_pending=1;view=1;pixel(180,90);if(dut.message!=78)$fatal(1,"route confirmation Chinese prompt");
   pixel(180,362);if(dut.message!=79)$fatal(1,"route confirmation English prompt");route_pending=0;
   drill_report=1;emergency=0;pixel(180,60);if(dut.message!=83)$fatal(1,"drill report title");
   pixel(80,224);if(dut.message!=84)$fatal(1,"publish confirmation time label");
   pixel(336,224);if(dut.message!=85)$fatal(1,"mute response time label");
   pixel(80,272);if(dut.message!=86)$fatal(1,"drill total time label");
   pixel(336,272);if(dut.message!=87)$fatal(1,"route adjustment count label");
   pixel(80,320);if(dut.message!=88)$fatal(1,"operation correction record label");
   pixel(256,224);if(dut.message!=24 || dut.character!=2)$fatal(1,"publish time seconds unit");
   pixel(512,224);if(dut.message!=24 || dut.character!=2)$fatal(1,"mute time seconds unit");
   pixel(256,272);if(dut.message!=24 || dut.character!=2)$fatal(1,"total time seconds unit");
   pixel(464,272);if(dut.message!=25 || dut.character!=1)$fatal(1,"route adjustment count value");
   pixel(208,320);if(dut.message!=94 || dut.character!=0)$fatal(1,"no correction value");
   drill_route_changes=4'd15;pixel(464,272);if(dut.character!=9)$fatal(1,"route count must saturate at 9");
   drill_corrected=1;pixel(208,320);if(dut.message!=96 || dut.character!=0)$fatal(1,"correction present value");
   drill_route_changes=1;drill_corrected=0;
   pixel(304,368);if(dut.message!=89)$fatal(1,"single drill grade");
   pixel(338,322);if(dut.text_on)$fatal(1,"duplicate drill grade");drill_report=0;emergency=1;
  // Capture the actual RTL font + geometry for visual review.
   for(n=0;n<20;n=n+1)begin
   case(n)
    0:begin view=1;zone=0;hazards=1;exits=2;alert_level=2;f=$fopen("sim/results/map_open.ppm","w");end
    1:begin view=1;hazards=15;exits=0;alert_level=3;f=$fopen("sim/results/map_closed.ppm","w");end
    2:begin view=2;f=$fopen("sim/results/health.ppm","w");end
    3:begin view=3;f=$fopen("sim/results/history.ppm","w");end
    4:begin scene_mode=1;view=1;hazards=1;exits=2;alert_level=2;f=$fopen("sim/results/drill.ppm","w");end
    5:begin scene_mode=2;view=1;f=$fopen("sim/results/mall_map.ppm","w");end
    6:begin view=0;event_type=0;f=$fopen("sim/results/mall_fire.ppm","w");end
    7:begin event_type=1;f=$fopen("sim/results/mall_crowd.ppm","w");end
    8:begin event_type=2;f=$fopen("sim/results/mall_power.ppm","w");end
    9:begin event_type=3;f=$fopen("sim/results/mall_escalator.ppm","w");end
    10:begin emergency=0;pending_confirm=1;alert_level=1;f=$fopen("sim/results/publish_confirm.ppm","w");end
    11:begin emergency=1;pending_confirm=0;clear_pending=1;alert_level=2;f=$fopen("sim/results/clear_confirm.ppm","w");end
     12:begin emergency=0;pending_confirm=0;clear_pending=0;drill_report=1;scene_mode=1;event_type=0;alert_level=0;f=$fopen("sim/results/drill_report.ppm","w");end
     13:begin emergency=1;drill_report=0;scene_mode=0;event_type=0;view=1;route_pending=1;alert_level=2;exits=2;f=$fopen("sim/results/route_pending.ppm","w");end
     14:begin route_pending=0;hazards=5;exits=2;alert_level=3;f=$fopen("sim/results/map_west.ppm","w");end
     15:begin hazards=10;exits=1;f=$fopen("sim/results/map_east.ppm","w");end
     16:begin en=0;image_background=1;view=0;scene_mode=0;event_type=0;hazards=1;exits=2;alert_level=2;bitmap_file=$fopen("TF_CARD_ROOT/FIRE.BMP","rb");f=$fopen("sim/results/campus_fire.ppm","w");end
     17:begin event_type=1;bitmap_file=$fopen("TF_CARD_ROOT/QUAKE.BMP","rb");f=$fopen("sim/results/campus_quake.ppm","w");end
     18:begin scene_mode=1;event_type=2;bitmap_file=$fopen("TF_CARD_ROOT/FLOOD.BMP","rb");f=$fopen("sim/results/drill_flood.ppm","w");end
     19:begin event_type=3;bitmap_file=$fopen("TF_CARD_ROOT/EVAC.BMP","rb");f=$fopen("sim/results/drill_evac.ppm","w");end
   endcase
   if(n>=16)begin
    if(bitmap_file==0)$fatal(1,"cannot open approved BMP for layout review");
    bitmap_bytes=$fread(bitmap,bitmap_file);$fclose(bitmap_file);
    if(bitmap_bytes!=921654)$fatal(1,"unexpected approved BMP size");
   end
   if((n>=6 && n<=9) || n>=16)begin
    // Deterministic varied PCM amplitudes for reviewing the real RTL bars.
    pcm_valid=1;
    for(m=0;m<1536;m=m+1)begin
     pcm_sample=((m/48)%7+2)*2048;@(negedge clk);
    end
    frame=1;@(negedge clk);frame=0;pcm_valid=0;
   end
   $fdisplay(f,"P3\n640 480\n255");
   for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
    pixel(xx,yy);$fdisplay(f,"%0d %0d %0d",composed_rgb[23:16],composed_rgb[15:8],composed_rgb[7:0]);
    if(draw !== ((yy>=8&&yy<24&&xx>=552) || (drill_report&&yy>=440&&yy<472) || ((pending_confirm||clear_pending)&&yy>=40) || (yy>=40&&yy<436) || (yy>=24&&yy<40&&xx>=16&&xx<320) ||
       (emergency&&scene_mode==2&&yy>=8&&yy<24&&xx>=16&&xx<160) || (emergency&&yy>=440&&yy<472)) && n<16)
       $fatal(1,"overlay coverage at %0d,%0d",xx,yy);
    if(n>=16 && yy>=44 && yy<432 && xx>=328 && xx<632 &&
       !(yy>=368&&yy<392&&xx<576) && draw)
       $fatal(1,"overlay obscures BMP instruction column");
   end
   $fclose(f);
  end
   pending_confirm=0;clear_pending=0;drill_report=0;route_pending=0;en=0;view=1;pixel(100,150);if(draw)$fatal(1,"cannot restore image view");
  emergency=0;pixel(1,60);if(draw)$fatal(1,"border persists in normal mode");
  pixel(20,28);if(!draw)$fatal(1,"normal mode must show selected scene/event");
  $display("PASS map pixels, SW3 all-zone flashing hazard, accessible prompt, current event summary, route safety and rendered previews");$finish;
 end
endmodule
