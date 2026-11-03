`timescale 1ns/1ps
module tb_media_sector_arbiter;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg ir=0,ar=0,busy=1,valid=0,done=0;
 reg [31:0] ilba=0,alba=0;
 wire ib,iv,id,ab,av,ad,req;wire [31:0] lba;
 integer transactions=0,image_bytes=0,audio_bytes=0;
 reg servicing_audio=0;
 media_sector_arbiter dut(.clk(clk),.rst_n(rst_n),
  .image_req(ir),.image_lba(ilba),.image_busy(ib),.image_valid(iv),.image_done(id),
  .audio_req(ar),.audio_lba(alba),.audio_busy(ab),.audio_valid(av),.audio_done(ad),
  .sector_req(req),.sector_lba(lba),.sector_busy(busy),.sector_valid(valid),.sector_done(done));
 always @(posedge clk)if(rst_n)begin
  if(iv&&av || id&&ad)$fatal(1,"sector delivered to both clients");
  if(valid && (servicing_audio ? (!av||iv) : (!iv||av)))$fatal(1,"wrong valid owner");
  if(done && (servicing_audio ? (!ad||id) : (!id||ad)))$fatal(1,"wrong done owner");
  if(iv)image_bytes=image_bytes+1;
  if(av)audio_bytes=audio_bytes+1;
 end
 task service(input [31:0] expected_lba,input is_audio);
  begin
   wait(req);@(negedge clk);
   if(lba!=expected_lba)$fatal(1,"LBA=%0d expected=%0d",lba,expected_lba);
   servicing_audio=is_audio;busy=1;
   repeat(3)begin valid=1;@(negedge clk);end
   valid=0;done=1;@(negedge clk);done=0;busy=0;
   transactions=transactions+1;
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  @(negedge clk);ir=1;ar=1;ilba=100;alba=200;
  @(negedge clk);ir=0;ar=0;ilba=999;alba=999;
  repeat(5)begin @(negedge clk);if(req)$fatal(1,"request while physical service busy");end
  busy=0;
  fork
   begin service(200,1);service(100,0);service(201,1);service(101,0);end
   begin
    wait(ad);@(negedge clk);ar=1;alba=201;@(negedge clk);ar=0;alba=999;
    wait(req&&lba==201);@(negedge clk);ir=1;ilba=101;@(negedge clk);ir=0;ilba=999;
   end
  join
  repeat(10)@(negedge clk);
  if(transactions!=4||image_bytes!=6||audio_bytes!=6||req||ib||ab)
   $fatal(1,"missing/duplicate sector or stuck busy");
  $display("PASS sector arbitration: simultaneous pulses, retained LBAs, alternating service and exclusive routing");
  $finish;
 end
 initial begin #10000;$fatal(1,"arbiter timeout");end
endmodule
