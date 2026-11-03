`timescale 1ns/1ps
module tb_terminal_control;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,rx=1,fs=0,next=0,ack=0,trig=0,clr=0,bri=0,con=0,scene=0;
 reg key_a_n=1,key_b_n=1;wire chord_a,chord_b,chord_pulse,chord_suppress;
 wire a_short,a_long,b_short,b_long;
 integer chords=0,singles=0,holds=0;
 reg [5:0] available=1;
 wire tx,ready,emergency,acknowledged,auto_on,alarm,test_audio;
 wire [2:0] bank; wire [15:0] id; wire [1:0] typ,sel,prio; wire [2:0] b,c,vol; wire [1:0] menu; wire [4:0] reveal;
 wire [5:0] seg_sel;wire [7:0] seg_data;reg [5:0] seen=0;
 terminal_sevenseg #(.CLOCK_HZ(12000)) display(.clk(clk),.rst_n(rst_n),
  .emergency(emergency),.event_type(typ),.selected_type(sel),.volume_level(vol),
  .brightness(b),.contrast(c),.adjust_menu(menu),.seg_sel(seg_sel),.seg_data(seg_data));
 terminal_control #(.CLOCK_HZ(200000),.UART_DIV(8),.PERIOD_FRAMES(3)) dut(
  .plan_valid(1'b0),.plan_data(30'd0),
 .clk(clk),.rst_n(rst_n),.uart_rx(rx),.uart_tx(tx),.next_press(next),.auto_ack_press(ack),
 .trigger_hold(trig),.clear_hold(clr),.scene_press(scene),.brightness_press(bri),.contrast_hold(con),.sensor_trigger(1'b0),
 .frame_start(fs),.available(available),.active_index(bank),.image_ready(ready),
 .emergency(emergency),.acknowledged(acknowledged),.auto_enabled(auto_on),.event_id(id),
 .event_type(typ),.selected_type(sel),.priority_level(prio),.brightness_level(b),.contrast_level(c),.volume_level(vol),.adjust_menu(menu),
 .reveal_step(reveal),.audio_test(test_audio),.alarm_enable(alarm));
 terminal_keys #(.CLOCK_HZ(1000)) ka(.clk(clk),.rst_n(rst_n),.key_n(key_a_n),
  .short_press(a_short),.long_press(a_long),.pressed_level(chord_a));
 terminal_keys #(.CLOCK_HZ(1000)) kb(.clk(clk),.rst_n(rst_n),.key_n(key_b_n),
  .short_press(b_short),.long_press(b_long),.pressed_level(chord_b));
 terminal_key_chord #(.CLOCK_HZ(1000)) chord(.clk(clk),.rst_n(rst_n),.key_a_level(chord_a),.key_b_level(chord_b),
  .chord_press(chord_pulse),.suppress_individual(chord_suppress));
 always @(posedge clk) if(rst_n) begin
  if(chord_pulse)chords=chords+1;
  if(!chord_suppress)begin
   if(a_short)singles=singles+1;if(b_short)singles=singles+1;
   if(a_long)holds=holds+1;if(b_long)holds=holds+1;
  end
 end
 task tick; begin @(negedge clk); end endtask
 task frame; begin tick();fs=1;tick();fs=0;tick();end endtask
 task byte_tx(input [7:0] value); integer k;begin
  rx=0;repeat(8)tick();for(k=0;k<8;k=k+1)begin rx=value[k];repeat(8)tick();end
  rx=1;repeat(12)tick();end endtask
 task packet(input [7:0] op,input [15:0] ident,input [7:0] t,p,input bad);begin
 byte_tx('haa);byte_tx('h55);byte_tx(op);byte_tx(ident[7:0]);byte_tx(ident[15:8]);byte_tx(t);byte_tx(p);
 byte_tx(op^ident[7:0]^ident[15:8]^t^p^bad); repeat(20)tick();end endtask
 // Decode real TX pins: validate the complete periodic snapshot, including XOR.
 integer status_packets=0,i,pos=0,scene_i,event_i; reg [7:0] v,bytes_rx[0:8];
 initial forever begin
  @(negedge tx);repeat(12)@(posedge clk);
  for(i=0;i<8;i=i+1)begin v[i]=tx;repeat(8)@(posedge clk);end
  if(tx!==1)$fatal(1,"TX stop bit");
  bytes_rx[pos]=v;
  if(pos==8)begin
   if(bytes_rx[0]!='haa||bytes_rx[1]!='h55||bytes_rx[2]!='h80||
      bytes_rx[8]!=(bytes_rx[2]^bytes_rx[3]^bytes_rx[4]^bytes_rx[5]^bytes_rx[6]^bytes_rx[7]))
      $fatal(1,"status packet framing/XOR");
   status_packets=status_packets+1;pos=0;
  end else pos=pos+1;
 end
 initial begin
  repeat(3)tick();rst_n=1;
  // Real synchronized/debounced inputs, including staggered release.
  key_a_n=0;repeat(50)tick();key_b_n=0;repeat(80)tick();
  if(!chord_suppress)$fatal(1,"chord did not suppress individual keys");
  key_a_n=1;repeat(70)tick();key_b_n=1;repeat(70)tick();
  if(chords!=1||singles!=0||holds!=0||chord_suppress)$fatal(1,"staggered release leaked single action");
  key_a_n=0;key_b_n=0;repeat(80)tick();key_a_n=1;key_b_n=1;repeat(70)tick();
  if(chords!=2||singles!=0||holds!=0)$fatal(1,"simultaneous release leaked single action");
  key_a_n=0;key_b_n=0;repeat(1200)tick();key_b_n=1;repeat(70)tick();key_a_n=1;repeat(70)tick();
  if(chords!=2||singles!=0||holds!=0)$fatal(1,"long chord must not switch scene or emit long action");
  key_b_n=0;repeat(70)tick();key_b_n=1;repeat(70)tick();
  if(singles!=1)$fatal(1,"single short action lost after chord");
  key_a_n=0;repeat(1200)tick();key_b_n=0;repeat(80)tick();
  key_a_n=1;key_b_n=1;repeat(70)tick();
  if(chords!=2||singles!=1||holds!=1)$fatal(1,"late second key created chord or duplicate action");
  frame();if(bank!=0||!ready||alarm)$fatal(1,"boot");
  repeat(70)begin
   tick();seen=seen|~seg_sel;
   if(seg_data!=(seg_sel==6'b111110 ? 8'ha1:seg_sel==6'b111011 ? 8'hb0:8'hf9))
    $fatal(1,"seven-segment scan/data mismatch");
  end
  if(seen!=63)$fatal(1,"seven-segment scan omitted digit");
  trig=1;tick();trig=0;if(auto_on)$fatal(1,"manual mode");
  next=1;tick();next=0;frame();if(bank!=1||ready||reveal!=0)$fatal(1,"missing normal fallback");
  packet(1,16'h1234,0,2,1);if(emergency)$fatal(1,"bad XOR accepted");
  packet(1,16'h1234,0,2,0);if(!emergency||!alarm)$fatal(1,"publish starts alert before image ready");
  frame();if(bank!=2||ready||!alarm)$fatal(1,"fallback commit");
  frame();if(!alarm)$fatal(1,"fallback alarm");
  packet(2,16'h1234,0,0,0);if(!acknowledged||alarm)$fatal(1,"ack");
  packet(1,16'h1234,0,2,0);if(!acknowledged||alarm)$fatal(1,"duplicate rearms");
  packet(3,16'h9999,0,0,0);if(!emergency||dut.result!=4)$fatal(1,"wrong ID clears");
  packet(1,16'h1235,1,1,0);if(id!='h1234||dut.result!=3)$fatal(1,"priority");
  available='h3f;packet(1,16'h1236,3,3,0);frame();frame();
  if(id!='h1236||bank!=5||!ready||!alarm||acknowledged)$fatal(1,"preemption");
  packet(3,16'h1236,0,0,0);frame();if(emergency||bank!=1||auto_on||alarm)$fatal(1,"restore");
  packet(1,16'h1236,3,3,0);if(emergency||dut.result!=2)$fatal(1,"cleared replay");
  packet(5,0,1,0,0);if(!test_audio)$fatal(1,"audio test");
  packet(5,0,0,0,0);if(test_audio)$fatal(1,"audio test off");
  // A scene change must revoke confirmation, even with a simultaneous publish.
  ack=1;tick();ack=0;tick();
  scene=1;ack=1;clr=1;tick();scene=0;ack=0;clr=0;tick();
  if(emergency||dut.pending_confirm||dut.scene_mode!=1||sel!=0)$fatal(1,"scene change did not take priority");
  // Restore campus and the previous selection for the remaining checks.
  scene=1;tick();scene=0;tick();scene=1;tick();scene=0;tick();
  repeat(3)begin clr=1;tick();clr=0;tick();end
  // KEY3 long selects within a scene; KEY2+KEY3 changes the scene.
  clr=1;tick();clr=0;if(sel!=0)$fatal(1,"event selection did not wrap from evacuation to fire");
  scene=1;tick();scene=0;if(dut.scene_mode!=1||sel!=0)$fatal(1,"scene chord did not select drill/reset event");
  ack=1;tick();ack=0;if(emergency||!dut.pending_confirm)$fatal(1,"first local publish press must arm confirmation");
  ack=1;tick();ack=0;if(!alarm||dut.displayed||vol!=2)$fatal(1,"confirmed local publish starts audio at level 3");
  // KEY4 long selects contrast; the following short press advances it.
  con=1;tick();con=0;bri=1;tick();bri=0;if(c!=1)$fatal(1,"image controls");
  // A local publish exactly on a frame edge must clear the old display receipt.
  frame();frame();if(!alarm||bank!=2||dut.scene_mode!=1)$fatal(1,"local drill event must retain fire image");
  ack=1;tick();ack=0;if(!acknowledged||alarm)$fatal(1,"local acknowledge");
  trig=1;tick();trig=0;if(!auto_on)$fatal(1,"emergency auto/manual toggle unavailable");
  trig=1;tick();trig=0;if(auto_on)$fatal(1,"emergency manual restore unavailable");
  clr=1;tick();clr=0;if(!emergency||!dut.clear_pending)$fatal(1,"first clear press must arm confirmation");
  clr=1;tick();clr=0;frame();if(emergency||bank!=1)$fatal(1,"confirmed local clear");
  con=1;tick();con=0;if(menu!=2)$fatal(1,"volume menu");
  con=1;tick();con=0;if(menu!=0)$fatal(1,"menu must wrap at three options");
  repeat(5)begin bri=1;tick();bri=0;tick();end
  if(b!=0)$fatal(1,"five brightness levels must wrap");
  // The two normal pages must rotate automatically as soon as both exist.
  trig=1;tick();trig=0;if(!auto_on)$fatal(1,"auto enable");
  repeat(4)frame();if(bank!=0||!ready)$fatal(1,"auto SAFETY to NORMAL");
  repeat(3)frame();if(bank!=1||!ready)$fatal(1,"auto NORMAL to SAFETY");
  // Automatic rotation must never enter an unavailable next normal page.
  available=6'b000010;repeat(6)frame();if(bank!=1||!ready)$fatal(1,"auto entered missing NORMAL");
  available=63;con=1;tick();con=0;tick();con=1;tick();con=0;
  if(menu!=2)$fatal(1,"volume selection");
  repeat(5)begin bri=1;tick();bri=0;tick();end
  if(vol!=2)$fatal(1,"five volume levels must wrap");
  ack=1;tick();ack=0;if(!dut.pending_confirm||emergency)$fatal(1,"new publish confirmation arm");
  ack=1;tick();ack=0;if(!alarm||vol!=2)$fatal(1,"publish restores audible level");
  bri=1;tick();bri=0;if(vol!=3||!alarm)$fatal(1,"live emergency volume");
  bri=1;tick();bri=0;if(vol!=4)$fatal(1,"mute level");
  bri=1;tick();bri=0;if(vol!=0)$fatal(1,"volume wraps to maximum");
  ack=1;tick();ack=0;bri=1;tick();bri=0;
  if(alarm||!acknowledged)$fatal(1,"volume must not undo acknowledged silence");
  // Clear the existing drill alert, then exercise all twelve scene/event choices.
  clr=1;tick();clr=0;tick();clr=1;tick();clr=0;tick();
  for(scene_i=1;scene_i<=3;scene_i=scene_i+1)begin
   for(event_i=0;event_i<4;event_i=event_i+1)begin
    if(dut.scene_mode!=scene_i%3||sel!=event_i)$fatal(1,"scene/event selection loop");
    ack=1;tick();ack=0;tick();
    if(emergency||!dut.pending_confirm)$fatal(1,"pre-alert published prematurely");
    ack=1;tick();ack=0;tick();frame();
    if(!emergency||typ!=event_i||!alarm||vol!=2)$fatal(1,"confirmed scene event");
    scene=1;tick();scene=0;tick();
    if(dut.scene_mode!=scene_i%3||typ!=event_i)$fatal(1,"emergency scene/event not locked");
    if(bank!=(scene_i%3==2 ?
       (event_i==0?2:event_i==1?5:event_i==2?1:4):event_i+2))$fatal(1,"scene bank mapping");
    clr=1;tick();clr=0;tick();
    if(!emergency||!dut.clear_pending||dut.scene_mode!=scene_i%3||sel!=event_i)
       $fatal(1,"first clear changed locked event/scene");
    clr=1;tick();clr=0;tick();if(emergency)$fatal(1,"second clear did not release");
    // Selecting a different event revokes a pending publication.
    ack=1;tick();ack=0;tick();clr=1;tick();clr=0;tick();
    if(dut.pending_confirm)$fatal(1,"stale publish confirmation survived selection");
   end
   if(scene_i<3)begin
    scene=1;tick();scene=0;tick();
    if(dut.scene_mode!=(scene_i+1)%3||sel!=0)$fatal(1,"scene chord mapping/reset");
   end
  end
  repeat(60000)tick();if(status_packets<2)$fatal(1,"no telemetry");
  $display("PASS UART commands, checksums, priority, fallback, acknowledge/clear, duplicate suppression, frame race, controls; %0d valid status packets",status_packets);
  $finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
