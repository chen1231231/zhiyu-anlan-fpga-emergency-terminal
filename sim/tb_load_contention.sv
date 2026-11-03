`timescale 1ns/1ps
// Decoder emits a complete 640-pixel row, not 170 isolated pixels per sector.
// Keep the real display reader running while delayed writes contend for SDRAM.
module tb_load_contention #(parameter TEST_DEPTH=2048);
    reg clk=0, pclk=0, rst_n=0;
    always #12.5 clk=~clk;
    always #20 pclk=~pclk;
    wire hs,vs,de;
    wire [11:0] x,y;
    video_timing_ctrl timing(.pclk(pclk),.rst_n(rst_n),.hsync(hs),.vsync(vs),.de(de),.x(x),.y(y));
    reg vsq=1;
    always @(posedge pclk) vsq<=vs;
    wire frame_start=vsq && !vs;
    integer slot=0;
    reg [4:0] tail=0;
    wire busy=slot<32 || slot>=1058 || tail!=0;
    wire refresh=slot>=1220;
    wire rr,rb,rg,wr,wb,wg,idle,re,we;
    wire [20:0] ra,wa;
    wire [31:0] wd;
    reg [7:0] returns=0;
    wire [7:0] mem_error;
    wire [23:0] rgb;
    wire valid,underflow;
    media_sdram_arbiter arb(.clk(clk),.rst_n(rst_n),.controller_busy(busy),.refresh_active(refresh),
        .read_request(rr),.read_busy(rb),.write_request(wr),.write_busy(wb),
        .read_grant(rg),.write_grant(wg),.idle(idle));
    media_frame_reader reader(.mem_clk(clk),.mem_rst_n(rst_n),.controller_init_done(1'b1),
        .controller_busy(busy),.refresh_active(refresh),.burst_grant(rg),.burst_request(rr),.burst_busy(rb),
        .app_rd_en(re),.app_rd_addr(ra),.sdram_rd_valid(returns[7]),.sdram_rd_data(32'h123456),
        .pix_clk(pclk),.pix_rst_n(rst_n),.frame_start(frame_start),.active_index(3'd0),
        .pixel_consume(de),.pixel_rgb(rgb),.pixel_valid(valid),.underflow(underflow),.reader_error());
    reg start=0,pv=0;
    media_frame_loader #(.FIFO_DEPTH(TEST_DEPTH)) loader(.clk(clk),.rst_n(rst_n),.load_start(start),.image_index(3'd1),
        .pixel_valid(pv),.pixel_rgb(24'h987654),.top_down(1'b1),.frame_commit(1'b0),.decode_error(8'd0),
        .controller_init_done(1'b1),.controller_busy(busy),.refresh_active(refresh),
        .burst_grant(wg),.burst_request(wr),.burst_busy(wb),.app_wr_en(we),.app_wr_addr(wa),
        .app_wr_data(wd),.memory_error(mem_error));
    integer peak=0,writes=0,reads=0;
    always @(posedge clk) if(rst_n) begin
        slot<=slot==1249?0:slot+1;
        if(we || re) tail<=8; else if(tail!=0) tail<=tail-1;
        returns<={returns[6:0],re};
        if(loader.fifo_count>peak) peak<=loader.fifo_count;
        if(we) writes<=writes+1;
        if(re) reads<=reads+1;
        if(mem_error!=0) $fatal(1,"background full-row write failed: error=%h peak=%0d reads=%0d writes=%0d",mem_error,peak,reads,writes);
    end
    integer row,p;
    initial begin
        #201 rst_n=1;
        @(posedge frame_start);
        wait(de);
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        for(row=0;row<12;row=row+1) begin
            // 320x240 upscaling emits TWO output rows per captured source row.
            // Alternate that case with the 640x480 single-row render burst.
            for(p=0;p<(row%2==0?1280:640);p=p+1) begin
                pv=1;@(negedge clk);pv=0;@(negedge clk);
            end
            // Three to four physical SPI sectors plus paced replay per BMP row.
            repeat(100003+row*137) @(negedge clk);
        end
        if(writes!=12*960 || reads==0) $fatal(1,"coverage missing");
        $display("PASS full-row background contention peak=%0d reads=%0d writes=%0d",peak,reads,writes);
        $finish;
    end
    initial begin #80000000;$fatal(1,"contention timeout");end
endmodule
