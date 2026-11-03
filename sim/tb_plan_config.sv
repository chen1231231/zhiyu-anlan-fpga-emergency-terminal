`timescale 1ns/1ps
module tb_plan_config;
 reg clk=0,rst_n=0,frame=0,publish=0;
 reg [29:0] plan=0;
 wire [2:0] active,volume;wire ready,emergency;wire [1:0] prio,scene,event_type;
 wire [1:0] view;
 wire [15:0] event_id;
 wire acknowledged,auto_enabled,pending_confirm;
 terminal_control #(.CLOCK_HZ(1000),.UART_DIV(8),.PERIOD_FRAMES(2)) dut(
  .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.uart_tx(),
  .next_press(1'b0),.auto_ack_press(publish),.trigger_hold(1'b0),.clear_hold(1'b0),.scene_press(1'b0),
  .brightness_press(1'b0),.contrast_hold(1'b0),.sensor_trigger(1'b0),.frame_start(frame),
  .available(6'h3f),.plan_valid(1'b1),.plan_data(plan),
  .active_index(active),.image_ready(ready),.emergency(emergency),.acknowledged(acknowledged),.auto_enabled(auto_enabled),
  .event_id(event_id),.scene_mode(scene),.event_type(event_type),.selected_type(),.priority_level(prio),
  .brightness_level(),.contrast_level(),.volume_level(volume),.adjust_menu(),.reveal_step(),
  .audio_test(),.pending_confirm(pending_confirm),.clear_pending(),.alarm_enable());
 terminal_safety #(.CLOCK_HZ(1000),.DEBOUNCE_CYCLES(2)) safety(
  .clk(clk),.rst_n(rst_n),.sw(4'd0),.emergency(emergency),.acknowledged(acknowledged),
  .event_id(event_id),.scene_mode(scene),.event_type(event_type),.next_press(1'b0),
  .page_hold(1'b0),.frame_start(frame),.auto_enabled(auto_enabled),
  .pending_confirm(pending_confirm),.operator_confirm(publish),
  .plan_valid(1'b1),.plan_emergency_seconds(plan[8:5]),.view(view));
 always #5 clk=~clk;
 task frame_pulse;begin @(negedge clk);frame=1;@(negedge clk);frame=0;end endtask
 task publish_press;begin @(negedge clk);publish=1;@(negedge clk);publish=0;end endtask
 initial begin
  // Mall defaults, event 0 priority 3, 3-second normal dwell, volume level 1.
  plan={8'h39,8'hab,2'd2,3'd1,4'd3,5'd3};
  repeat(3)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  if(scene!=2||volume!=1)$fatal(1,"plan defaults not applied scene=%d volume=%d",scene,volume);
  repeat(179)frame_pulse();
  if(active!=0)$fatal(1,"configured dwell ignored active=%d",active);
  frame_pulse();frame_pulse();
  if(active!=1)$fatal(1,"normal configured dwell never advanced active=%d",active);
  publish_press();publish_press();frame_pulse();
  if(!emergency||event_type!=0||prio!=3||volume!=1||active!=2||!ready)
   $fatal(1,"configured publish mismatch emergency=%b type=%d priority=%d volume=%d active=%d",emergency,event_type,prio,volume,active);
  if(view!=1)$fatal(1,"published alert did not open map");
  repeat(178)frame_pulse();
  if(view!=1)$fatal(1,"emergency dwell ignored configured 3 seconds");
  frame_pulse();
  if(view!=0)$fatal(1,"emergency configured dwell never advanced");
  $display("PASS configurable plan: defaults, normal/emergency dwell boundaries, priority and scene selection");
  $finish;
 end
endmodule
