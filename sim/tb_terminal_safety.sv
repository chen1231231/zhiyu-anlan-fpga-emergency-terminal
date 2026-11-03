`timescale 1ns/1ps
module tb_terminal_safety;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [3:0] sw=8;
 reg ack=0,clear_key=0,next_key=0,hold_key=0,scene_key=0;
 reg frame=0;
 wire emergency,acknowledged,trigger,alarm;
 wire [15:0] id;wire [1:0] event_type,zone,exits,view;
 wire [3:0] stable;wire block_extra,startup;
 wire [3:0] hazards;
 wire [9:0] elapsed;wire [67:0] history;wire [2:0] count;
 wire [1:0] scene;wire [7:0] history_scene;wire auto_on;
 wire [1:0] alert_level,recommended_exit;wire [6:0] route_score,drill_score;
 wire route_pending,drill_report,drill_corrected;wire [7:0] drill_confirm_seconds;
 wire [9:0] drill_ack_seconds,drill_total_seconds;wire [3:0] drill_route_changes;
 integer pulses=0,z,b;
 integer s,k;reg [3:0] expected_mask;reg [1:0] old_level,old_exits;
 function [3:0] mask_for(input [2:0] code);
  begin mask_for=!code[2] ? (4'b0001<<code[1:0]):code[1:0]==1 ? 5:code[1:0]==2 ? 10:15;end
 endfunction
 terminal_safety #(.CLOCK_HZ(1000),.DEBOUNCE_CYCLES(4)) dut(
  .plan_valid(1'b0),.plan_emergency_seconds(4'd0),
 .clk(clk),.rst_n(rst_n),.sw(sw),.emergency(emergency),.acknowledged(acknowledged),
 .event_id(id),.scene_mode(scene),.event_type(event_type),.next_press(next_key),.page_hold(scene_key),
  .frame_start(frame),.auto_enabled(auto_on),.pending_confirm(control.pending_confirm),.operator_confirm(ack),
 .sensor_trigger(trigger),.stable_sw(stable),.zone(zone),.extra_block(block_extra),.exits_open(exits),.hazard_mask(hazards),.history_scene(history_scene),
  .view(view),.elapsed(elapsed),.history(history),.history_count(count),
  .alert_level(alert_level),.route_pending(route_pending),.recommended_exit(recommended_exit),.route_score(route_score),
  .drill_report(drill_report),.drill_score(drill_score),.drill_confirm_seconds(drill_confirm_seconds),
  .drill_ack_seconds(drill_ack_seconds),.drill_total_seconds(drill_total_seconds),
  .drill_route_changes(drill_route_changes),.drill_corrected(drill_corrected),.startup(startup));
 terminal_control #(.CLOCK_HZ(1000),.UART_DIV(8)) control(
  .plan_valid(1'b0),.plan_data(30'd0),
 .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.uart_tx(),.next_press(next_key),.auto_ack_press(ack && !route_pending),
 .trigger_hold(hold_key),.clear_hold(clear_key),.scene_press(scene_key),.brightness_press(1'b0),.contrast_hold(1'b0),
 .sensor_trigger(trigger),.frame_start(1'b0),.available(6'b0),.event_id(id),.event_type(event_type),
 .emergency(emergency),.acknowledged(acknowledged),.alarm_enable(alarm),
 .scene_mode(scene),.auto_enabled(auto_on));
 always @(posedge clk) if(trigger)pulses=pulses+1;
 task tick;begin @(negedge clk);end endtask
 initial begin
  repeat(3)tick();rst_n=1;repeat(20)tick();
  if(emergency||pulses)$fatal(1,"boot-high must not publish");
  sw=0;repeat(16)tick();sw=8;tick();sw=0;repeat(16)tick();
  if(emergency||pulses)$fatal(1,"switch bounce published");
  for(z=0;z<4;z=z+1)for(b=0;b<2;b=b+1)begin
   sw=z+(b<<2);repeat(16)tick();sw=sw|8;repeat(16)tick();
   // The first sensor edge is a pre-alert; a second edge confirms publication.
   if(!emergency) begin sw=0;repeat(16)tick();sw=z+(b<<2);repeat(16)tick();sw=sw|8;repeat(16)tick();end
   if(!emergency||!alarm||zone!=z||block_extra!=b||view!=1)$fatal(1,"sensor publication/snapshot");
   expected_mask=mask_for({b[0],z[1:0]});
   if(hazards!==expected_mask || exits!=={!(expected_mask[1]||expected_mask[3]),!(expected_mask[0]||expected_mask[2])})$fatal(1,"route matrix zone%0d group%0d",z,b);
   if(alert_level!==(b?3:2))$fatal(1,"warning level must match published scope");
   if(history[14]!==b[0])$fatal(1,"history all-zone flag");
   sw=0;repeat(16)tick();if(zone!=z||block_extra!=b)$fatal(1,"live switch changed locked route");
    if((z!=0||b!=0)&&!route_pending)$fatal(1,"real scene route change must wait for confirmation");
   repeat(1100)tick();if(elapsed<1)$fatal(1,"event timer");
   repeat(120)begin frame=1;tick();frame=0;tick();end
   if(view!=0)$fatal(1,"automatic emergency map to picture rotation");
   repeat(120)begin frame=1;tick();frame=0;tick();end
   if(view!=1)$fatal(1,"automatic emergency picture to map rotation");
   next_key=1;tick();next_key=0;tick();if(view!=0)$fatal(1,"image view unavailable");
   hold_key=1;tick();hold_key=0;tick();
   if(auto_on)$fatal(1,"emergency KEY2 long did not select manual");
   repeat(130)begin frame=1;tick();frame=0;tick();end
   if(view!=0)$fatal(1,"manual emergency view changed automatically view=%0d auto=%0d",view,auto_on);
   hold_key=1;tick();hold_key=0;tick();
   if(!auto_on)$fatal(1,"emergency KEY2 long did not restore auto");
   scene_key=1;tick();scene_key=0;tick();if(view!=2)$fatal(1,"diagnostics view");
   scene_key=1;tick();scene_key=0;tick();if(view!=3)$fatal(1,"history view");
   ack=1;tick();ack=0;repeat(3)tick();
   if(z!=0||b!=0) begin
    if(!emergency||!alarm||acknowledged||history[11:10]!=0)$fatal(1,"route confirmation must not mute audio");
    if(route_pending||zone!=0||block_extra!=0)$fatal(1,"KEY3 did not accept pending real-scene route");
    ack=1;tick();ack=0;repeat(3)tick();
   end
   if(!emergency||alarm||history[11:10]!=1)$fatal(1,"second KEY3 must mute without clearing");
   repeat(1100)tick();if(!emergency)$fatal(1,"time must not automatically clear");
   clear_key=1;tick();clear_key=0;repeat(3)tick();
   if(!emergency)$fatal(1,"first clear must wait for confirmation");
   clear_key=1;tick();clear_key=0;repeat(3)tick();
   if(emergency||history[11:10]!=2)$fatal(1,"clear/history");
  end
  if(pulses!=16||count!=4)$fatal(1,"debounced pre-alert/confirmation edges / bounded four-record history");
   repeat(4)begin clear_key=1;tick();clear_key=0;tick();end
   scene_key=1;tick();scene_key=0;tick();
   ack=1;tick();ack=0;repeat(6100)tick();
   if(alert_level!=1)$fatal(1,"pending warning must be yellow");
   ack=1;tick();ack=0;repeat(4)tick();
   if(scene!=1||alert_level!=2||history_scene[1:0]!=1||history_scene[3:2]!=0)$fatal(1,"drill publish/scene/level");
   sw=1;repeat(16)tick();
   if(zone!=1||route_pending)$fatal(1,"drill route must adapt automatically");
   ack=1;tick();ack=0;repeat(8)tick();
   clear_key=1;tick();clear_key=0;tick();clear_key=1;tick();clear_key=0;repeat(5)tick();
   if(!drill_report||drill_confirm_seconds<1||drill_route_changes==0||drill_score>=100)
    $fatal(1,"drill assessment report/metrics report=%d confirm=%d routes=%d score=%d",drill_report,drill_confirm_seconds,drill_route_changes,drill_score);
   next_key=1;tick();next_key=0;repeat(3)tick();if(drill_report)$fatal(1,"KEY2 must dismiss drill report");
  rst_n=0;tick();rst_n=1;repeat(20)tick();if(count!=0||history!=0)$fatal(1,"history must be volatile");
  // Exercise every scope in campus, drill and mall, including reduction from
  // red back to orange, held-route consistency, cancellation, and audio safety.
  for(s=0;s<3;s=s+1)begin
   rst_n=0;sw=0;tick();rst_n=1;repeat(20)tick();
   for(k=0;k<s;k=k+1)begin scene_key=1;tick();scene_key=0;tick();end
   ack=1;tick();ack=0;tick();ack=1;tick();ack=0;repeat(5)tick();
   if(!emergency||!alarm||scene!=s)$fatal(1,"scene scope test setup");
   for(k=1;k<=8;k=k+1)begin
    old_level=alert_level;old_exits=exits;sw=k%8;repeat(20)tick();
    if(s!=1)begin
     if(!route_pending||alert_level!==old_level||exits!==old_exits)$fatal(1,"badge changed before accepted route");
     ack=1;tick();ack=0;repeat(5)tick();
    end
    expected_mask=mask_for(sw[2:0]);
    if(hazards!==expected_mask||route_pending||!alarm||acknowledged)$fatal(1,"scope update muted or wrong mask scene%0d code%0d",s,sw);
    if(alert_level!==(sw[2]?3:2))$fatal(1,"badge did not follow accepted scope");
    if(exits!=={!(expected_mask[1]||expected_mask[3]),!(expected_mask[0]||expected_mask[2])})$fatal(1,"scope exit mismatch");
    if(history[14:12]!==sw[2:0])$fatal(1,"history scope stale");
   end
   if(s!=1)begin
    sw=5;repeat(20)tick();if(!route_pending)$fatal(1,"half-zone pending missing");
    sw=0;repeat(20)tick();if(route_pending)$fatal(1,"returning switches must cancel pending route");
   end
   if(s==0)begin
    repeat(61000)tick();if(alert_level!=2)$fatal(1,"elapsed time must not disagree with single-zone route");
   end
   ack=1;tick();ack=0;repeat(5)tick();if(alarm||!acknowledged)$fatal(1,"explicit mute missing");
   sw=6;repeat(20)tick();
   if(s!=1)begin ack=1;tick();ack=0;repeat(5)tick();end
   if(alarm||!acknowledged||hazards!=10)$fatal(1,"route update must preserve an existing mute");
  end
   $display("PASS safety switch debounce, four-level warning, adaptive drill route, locked real route, assessment and history");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
