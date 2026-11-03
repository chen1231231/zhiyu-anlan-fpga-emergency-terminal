`timescale 1ns/1ps
module tb_scale_load;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,valid=0,ended=0;
    reg [31:0] size,offset;
    reg [7:0] data;
    wire pv,commit,done,td,load_done;
    wire [23:0] rgb;
    wire [15:0] px,py;
    wire [7:0] err,memerr;
    wire wr,req,burst;
    wire [20:0] addr;
    wire [31:0] word;
    wire [5:0] complete;
    reg [2:0] bank=0;
    integer w,h,mode,pol,count,writes,commits;
    integer sx,sy,ox,oy,expected_addr;
    reg [23:0] expected;
    bmp_scale_decoder d(.clk(clk),.rst_n(rst_n),.file_start(start),.file_size(size),
        .file_valid(valid),.file_byte(data),.file_byte_offset(offset),.file_end(ended),.upstream_error(8'd0),
        .header_accepted(),.pixel_valid(pv),.pixel_rgb(rgb),.pixel_x(px),.pixel_y(py),
        .frame_commit(commit),.bmp_done(done),.bmp_error(err),.top_down(td),.pixel_offset(),.row_stride());
    media_frame_loader l(.clk(clk),.rst_n(rst_n),.load_start(start),.image_index(bank),.pixel_valid(pv),.pixel_rgb(rgb),
        .top_down(td),.frame_commit(commit),.decode_error(err),.load_busy(),.load_done(load_done),.image_complete(complete),
        .memory_error(memerr),.controller_init_done(1'b1),.controller_busy(1'b0),.refresh_active(1'b0),
        .burst_grant(req),.burst_request(req),.burst_busy(burst),.app_wr_en(wr),.app_wr_addr(addr),.app_wr_mask(),.app_wr_data(word));
    function automatic [23:0] pattern(input integer x,y);
        pattern={8'(x^y),8'(y),8'(x)};
    endfunction
    always @(posedge clk) if(rst_n) begin
        if(pv) begin
            ox=count%640;oy=count/640;
            sx=mode==0 ? ox/2:mode==2 ? ox+ox/4:ox;
            sy=mode==0 ? oy/2:mode==2 ? oy+oy/4:oy;
            expected=pattern(sx,sy);
            if(rgb!==expected || px!=ox || py!=oy) $fatal(1,"scale mismatch bank%0d pixel%0d got%h expected%h xy%0d,%0d",bank,count,rgb,expected,px,py);
            count=count+1;
        end
        if(wr) begin
            ox=writes%640;oy=writes/640;
            expected_addr=bank*307200+(pol==0 ? oy:479-oy)*640+ox;
            sx=mode==0 ? ox/2:mode==2 ? ox+ox/4:ox;
            sy=mode==0 ? oy/2:mode==2 ? oy+oy/4:oy;
            if(addr!==21'(expected_addr) || word!=={8'd0,pattern(sx,sy)}) $fatal(1,"SDRAM bank/orientation mismatch bank%0d write%0d addr%0d expected%0d",bank,writes,addr,expected_addr);
            writes=writes+1;
        end
        if(commit) commits=commits+1;
    end
    task send(input [7:0] b);
        begin
            @(negedge clk);valid=1;data=b;
            @(negedge clk);valid=0;offset=offset+1;
            // Stress faster than production's 16-cycle byte spacing.
            repeat(3) @(negedge clk);
        end
    endtask
    task dword(input integer n);
        begin send(n[7:0]);send(n[15:8]);send(n[23:16]);send(n[31:24]); end
    endtask
    task header(input integer bpp);
        begin
            send("B");send("M");dword(size);dword(0);dword(54);dword(40);
            dword(w);dword(pol==0 ? -h:h);send(1);send(0);send(bpp);send(0);
            dword(0);dword(w*h*3);dword(0);dword(0);dword(0);dword(0);
        end
    endtask
    task begin_file;
        begin
            count=0;writes=0;commits=0;offset=0;size=w*h*3+54;
            @(negedge clk);start=1;
            @(negedge clk);start=0;
        end
    endtask
    task finish_file;
        begin @(negedge clk);ended=1;@(negedge clk);ended=0; end
    endtask
    integer ix,iy,timeout;
    initial begin
        count=0;writes=0;commits=0;mode=0;pol=0;offset=0;size=0;
        repeat(5) @(negedge clk);rst_n=1;
        for(bank=0;bank<6;bank=bank+1) begin
            mode=bank/2;pol=bank%2;
            w=mode==0 ? 320:mode==1 ? 640:800;
            h=mode==0 ? 240:mode==1 ? 480:600;
            begin_file();header(24);
            for(iy=0;iy<h;iy=iy+1) for(ix=0;ix<w;ix=ix+1) begin
                send(ix[7:0]);send(iy[7:0]);send(8'(ix^iy));
            end
            finish_file();timeout=0;
            while(!load_done && timeout<10000) begin @(negedge clk);timeout=timeout+1;end
            if(timeout==10000 || err || memerr || !complete[bank] || count!=307200 || writes!=307200 || commits!=1)
                $fatal(1,"completion failed bank%0d pixels%0d writes%0d commits%0d err%h mem%h",bank,count,writes,commits,err,memerr);
            $display("PASS size %0dx%0d top_down=%0d bank=%0d every pixel + SDRAM address checked",w,h,!pol,bank);
        end
        bank=5;mode=1;w=640;h=480;begin_file();header(32);finish_file();
        repeat(30) @(negedge clk);
        if(err!=8'h34 || complete[5] || commits) $fatal(1,"invalid BPP accepted");
        begin_file();header(24);repeat(10) send(8'h20);finish_file();
        repeat(30) @(negedge clk);
        if(err!=8'h37 || complete[5] || commits) $fatal(1,"truncated BMP accepted");
        $display("PASS corrupt/truncated BMP never committed; ALL SCALE/LOAD TESTS PASSED");$finish;
    end
    initial begin #2000000000;$fatal(1,"timeout");end
endmodule
