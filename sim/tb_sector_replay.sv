`timescale 1ns/1ps
module tb_sector_replay;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,req=0;
    reg [31:0] lba=0;
    wire busy,valid,done,rreq;
    wire [7:0] byte_out,error_out;
    wire [8:0] index_out;
    wire [31:0] rlba;
    reg rb=0,rv=0,rd=0;
    reg [7:0] rbyte=0,rerror=0;
    reg [8:0] rindex=0;
    integer mode=0,attempts=0,delivered=0,k,limit;
    sd_sector_replay_buffer dut(.clk(clk),.rst_n(rst_n),.sector_req(req),.sector_lba(lba),
        .sector_busy(busy),.sector_valid(valid),.sector_byte(byte_out),.sector_byte_index(index_out),
        .sector_done(done),.sector_error(error_out),.reader_req(rreq),.reader_lba(rlba),
        .reader_busy(rb),.reader_valid(rv),.reader_byte(rbyte),.reader_byte_index(rindex),
        .reader_done(rd),.reader_error(rerror));
    initial forever begin
        wait(rreq);@(negedge clk);rb=1;attempts=attempts+1;
        if(rlba!=32'h12345)$fatal(1,"retry changed admitted LBA");
        rerror=0;limit=(mode==3 && attempts==1)?400:512;
        for(k=0;k<limit;k=k+1)begin
            rv=1;rindex=(mode==2 && attempts==1 && k==20)?19:k;
            rbyte=k^8'ha5;@(negedge clk);
        end
        rv=0;
        if((mode==1 && attempts==1)||mode==4)rerror=3;
        rd=1;@(negedge clk);rd=0;rb=0;
    end
    always @(posedge clk) if(valid)begin
        if(index_out!==9'(delivered) || byte_out!==(8'(delivered)^8'ha5))
            $fatal(1,"bad/duplicated replay byte %0d",delivered);
        delivered=delivered+1;
    end
    task run(input integer kind,expected_attempts,expected_bytes);
        begin
            @(negedge clk);mode=kind;attempts=0;delivered=0;lba=32'h12345;req=1;
            @(negedge clk);req=0;lba=32'hdeadbeef;
            wait(done);@(negedge clk);
            if(attempts!=expected_attempts || delivered!=expected_bytes || error_out!=(kind==4?3:0))
                $fatal(1,"recovery failed mode=%0d attempts=%0d bytes=%0d error=%h",kind,attempts,delivered,error_out);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        run(1,2,512);run(2,2,512);run(3,2,512);run(4,3,0);run(0,1,512);
        $display("PASS bounded sector retries: timeout, order, truncation, persistent failure and next request");
        $finish;
    end
    initial begin #3000000;$fatal(1,"replay timeout");end
endmodule
