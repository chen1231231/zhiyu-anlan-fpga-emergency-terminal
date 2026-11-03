`timescale 1ns/1ps
module tb_media_recovery;
 reg clk=0,rst_n=0,memory_ready=0,ingest_busy=0,ingest_done=0,runtime_fault=0,retry_tick=0;
 reg [7:0] ingest_error=0;
 wire start,recovering,healthy;
 terminal_media_recovery #(.RETRY_TICKS(2)) dut(
  .clk(clk),.rst_n(rst_n),.memory_ready(memory_ready),.ingest_busy(ingest_busy),
  .ingest_done(ingest_done),.ingest_error(ingest_error),.runtime_fault(runtime_fault),
  .retry_tick(retry_tick),
  .ingest_start(start),.recovery_active(recovering),.media_healthy(healthy));
 always #5 clk=~clk;
 task pulse_done(input [7:0] code);begin
  @(negedge clk);ingest_error=code;ingest_done=1;@(negedge clk);ingest_done=0;
 end endtask
 task retry;begin
  repeat(2)begin @(negedge clk);retry_tick=1;@(negedge clk);retry_tick=0;end
 end endtask
 initial begin
  repeat(2)@(negedge clk);rst_n=1;memory_ready=1;
  wait(start);@(negedge clk);ingest_busy=1;repeat(2)@(negedge clk);ingest_busy=0;
  pulse_done(8'h80);
  if(!recovering||healthy)$fatal(1,"failed ingest did not enter recovery");
  retry();
  wait(start);@(negedge clk);ingest_busy=1;repeat(2)@(negedge clk);ingest_busy=0;
  pulse_done(0);
  if(recovering||!healthy)$fatal(1,"successful rescan did not recover");
  @(negedge clk);runtime_fault=1;@(negedge clk);runtime_fault=0;
  if(!recovering||healthy)$fatal(1,"runtime fault did not schedule recovery");
  retry();
  wait(start);@(negedge clk);ingest_busy=1;repeat(2)@(negedge clk);ingest_busy=0;
  pulse_done(0);
  if(recovering||!healthy)$fatal(1,"runtime recovery did not complete");
  $display("PASS media self-healing: boot, failed scan retry, runtime fault and automatic recovery");
  $finish;
 end
 initial begin #2000;$fatal(1,"recovery timeout");end
endmodule
