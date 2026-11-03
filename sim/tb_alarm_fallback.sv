`timescale 1ns/1ps
module tb_alarm_fallback;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,en=0,fault=0,starved=0;reg [2:0] vol=2;
 wire signed [15:0] sample;wire active;
 integer i,level,expected_amplitude,edges=0;reg prev;
 terminal_alarm_fallback dut(.clk(clk),.rst_n(rst_n),.sample_valid(1'b1),.alarm_enable(en),
 .pcm_fault(fault),.underflow(starved),.volume_level(vol),.pcm(16'sd123),.sample_out(sample),.fallback_active(active));
 task tick;begin @(negedge clk);end endtask
 initial begin
  repeat(3)tick();rst_n=1;en=1;fault=1;tick();
  if(!active||sample!=-6000)$fatal(1,"missing file must sound without TF");
  for(level=0;level<5;level=level+1)begin
   vol=level;tick();
   case(level) 0:expected_amplitude=12000;1:expected_amplitude=9000;
    2:expected_amplitude=6000;3:expected_amplitude=3000;default:expected_amplitude=0;endcase
   if(sample!=expected_amplitude && sample!=-expected_amplitude)$fatal(1,"fallback volume level %0d",level);
  end
  vol=2;tick();
  prev=sample>0;
  for(i=0;i<48000;i=i+1)begin
   tick();if((sample>0)!=prev)edges=edges+1;prev=sample>0;
   if(i>36000&&i<47900&&sample!=0)$fatal(1,"alarm silent quarter");
  end
  if(edges<1000)$fatal(1,"alternating alarm frequency");
  vol=4;tick();if(sample!=0)$fatal(1,"zero volume");
  vol=0;fault=0;tick();if(active||sample!=123)$fatal(1,"valid PCM recovery");
  starved=1;repeat(11999)tick();if(active)$fatal(1,"short starvation must not interrupt speech");
  repeat(3)tick();if(!active)$fatal(1,"long starvation fallback");
  starved=0;tick();if(active)$fatal(1,"recovered PCM");
  en=0;fault=1;tick();if(active)$fatal(1,"ACK must disable fallback");
  $display("PASS TF-independent alarm, frequency/cadence, five levels, starvation recovery and mute");$finish;
 end
endmodule
