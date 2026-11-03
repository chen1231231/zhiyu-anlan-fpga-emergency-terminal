`timescale 1ns/1ps

// Real loader/reader/control/FIFO/video logic with a latency-bearing SDRAM
// application-port model. Checks every displayed pixel while other banks load.
module tb_terminal_memory;
    localparam WORDS = 640*480;
    reg mem_clk = 0, pix_clk = 0, ctrl_clk = 0;
    always #12.5 mem_clk = ~mem_clk;
    always #20 pix_clk = ~pix_clk;
    always #10 ctrl_clk = ~ctrl_clk;
    reg rst_n = 0;
    reg load_start = 0, pixel_valid = 0, frame_commit = 0;
    reg [2:0] load_index = 0;
    reg [23:0] pixel_rgb = 0;
    reg top_down = 1;
    wire [5:0] complete;
    wire load_done;
    wire [7:0] memory_error;
    wire wr_en, rd_en;
    wire [20:0] wr_addr, rd_addr;
    wire [31:0] wr_data;
    wire read_req, write_req, read_busy, write_busy, read_grant, write_grant;
    wire idle;
    reg player_enable = 0;
    reg next_event = 0;
    wire [2:0] active_index;
    wire vs, hs, de, video_clk;
    wire [23:0] rgb;
    wire underflow;
    wire [7:0] video_error;
    wire frame_start;
    integer slot = 0;
    reg [4:0] tail = 0;
    wire refresh_active = slot >= 1220;
    wire controller_busy = slot < 32 || slot >= 1026 || tail != 0;
    reg [31:0] memory [0:WORDS*6-1];
    reg [7:0] return_pipe = 0;
    reg [31:0] data_pipe [0:7];
    wire rd_valid = return_pipe[7];
    wire [31:0] rd_data = data_pipe[7];
    integer j;
    integer reads = 0, writes = 0, overlapping_grants = 0;
    integer first_display_time = 0, all_loaded_time = 0;
    integer displayed_frames = 0, checked_pixels = 0, background_reads = 0;
    integer x = 0, y = 0;
    reg de_q = 0;
    reg frame_check = 0;
    reg [2:0] display_index;

    function automatic [23:0] pattern(input integer bank, input integer offset);
        pattern = (24'h315a7c * (bank+1)) ^ offset;
    endfunction

    media_sdram_arbiter arbiter (
        .clk(mem_clk), .rst_n(rst_n), .controller_busy(controller_busy),
        .refresh_active(refresh_active), .read_request(read_req),
        .read_busy(read_busy), .write_request(write_req), .write_busy(write_busy),
        .read_grant(read_grant), .write_grant(write_grant), .idle(idle)
    );
    media_frame_loader loader (
        .clk(mem_clk), .rst_n(rst_n), .load_start(load_start),
        .image_index(load_index), .pixel_valid(pixel_valid), .pixel_rgb(pixel_rgb),
        .top_down(top_down), .frame_commit(frame_commit), .decode_error(8'd0),
        .load_busy(), .load_done(load_done), .image_complete(complete),
        .memory_error(memory_error), .controller_init_done(1'b1),
        .controller_busy(controller_busy), .refresh_active(refresh_active),
        .burst_request(write_req), .burst_busy(write_busy), .burst_grant(write_grant),
        .app_wr_en(wr_en), .app_wr_addr(wr_addr), .app_wr_mask(), .app_wr_data(wr_data)
    );
    wire [11:0] vx,vy;
    wire image_ready;
    reg trigger_event=0, clear_event=0;
    reg vs_q=1, reader_frame=0;
    wire [5:0] available;
    genvar g;
    generate for(g=0;g<6;g=g+1)begin:sync_av
      sync_2ff ff(.clk(pix_clk),.rst_n(rst_n),.async_in(complete[g] && player_enable),.sync_out(available[g]));
    end endgenerate
    video_timing_ctrl timing(.pclk(pix_clk),.rst_n(rst_n),.hsync(hs),.vsync(vs),.de(de),.x(vx),.y(vy));
    assign frame_start=vs_q && !vs;
    always @(posedge pix_clk)begin vs_q<=vs;reader_frame<=frame_start;end
    terminal_control #(.PERIOD_FRAMES(60000)) control(.clk(pix_clk),.rst_n(rst_n),.uart_rx(1'b1),
        .plan_valid(1'b0),.plan_data(30'd0),
       .next_press(next_event),.auto_ack_press(trigger_event),.trigger_hold(1'b0),.clear_hold(clear_event),.scene_press(1'b0),
       .brightness_press(1'b0),.contrast_hold(1'b0),.frame_start(frame_start),.available(available),
       .active_index(active_index),.image_ready(image_ready));
    media_frame_reader reader(.mem_clk(mem_clk),.mem_rst_n(rst_n),.controller_init_done(1'b1),
       .controller_busy(controller_busy),.refresh_active(refresh_active),.burst_request(read_req),
       .burst_busy(read_busy),.burst_grant(read_grant),.app_rd_en(rd_en),.app_rd_addr(rd_addr),
       .sdram_rd_valid(rd_valid),.sdram_rd_data(rd_data),.pix_clk(pix_clk),.pix_rst_n(rst_n),
       .frame_start(reader_frame && image_ready),.active_index(active_index),.pixel_consume(de && image_ready),
       .pixel_rgb(rgb),.pixel_valid(),.underflow(underflow),.reader_error(video_error));

    always @(posedge mem_clk) begin
        if (rst_n) begin
            slot <= slot == 1249 ? 0 : slot + 1;
            if (wr_en || rd_en) tail <= 8;
            else if (tail != 0) tail <= tail - 1'b1;
            return_pipe <= {return_pipe[6:0], rd_en};
            if (rd_en) data_pipe[0] <= memory[rd_addr];
            for (j=1; j<8; j=j+1) data_pipe[j] <= data_pipe[j-1];
            if (wr_en) begin
                memory[wr_addr] <= wr_data;
                writes <= writes + 1;
                if (player_enable && complete[wr_addr / WORDS])
                    $fatal(1, "write into a committed bank");
            end
            if (rd_en) begin
                reads <= reads + 1;
                if (!complete[rd_addr / WORDS]) $fatal(1, "read from incomplete bank");
                if (complete != 63) background_reads <= background_reads + 1;
            end
            if (wr_en && rd_en) $fatal(1, "simultaneous read/write commands");
            if (write_grant && read_grant) $fatal(1, "double grant");
            if (idle && read_req && write_req && !controller_busy && !refresh_active) begin
                overlapping_grants <= overlapping_grants + 1;
                if (!read_grant || write_grant) $fatal(1, "read priority violated");
            end
            if (memory_error != 0) $fatal(1, "loader error %h", memory_error);
            if (complete[0] && idle && !controller_busy && !refresh_active)
                player_enable <= 1;
        end
    end

    // A switch request during loading may select only a committed bank.
    always @(negedge pix_clk) begin
        if (rst_n) begin
            if (frame_start) begin
                x = 0; y = 0;
                frame_check = 0;
            end
            if (de) begin
                if (!de_q) begin
                    frame_check = image_ready;
                    x = 0;
                    display_index = active_index;
                end
                if (frame_check) begin
                    if (rgb !== pattern(display_index, y*640+x))
                        $fatal(1,"pixel mismatch bank=%0d x=%0d y=%0d rgb=%h expected=%h", display_index,x,y,rgb,pattern(display_index,y*640+x));
                    checked_pixels = checked_pixels + 1;
                    if (!first_display_time) first_display_time = $time;
                    if (x==639 && y==479) displayed_frames = displayed_frames + 1;
                end
                x = x + 1;
            end
            if (de_q && !de) y = y + 1;
            de_q = de;
            if (video_error != 0) $fatal(1,"video error %h",video_error);
            if (underflow) $fatal(1,"video underflow");
        end
    end

    task automatic load_image(input integer bank);
        integer k, offset;
        begin
            @(negedge mem_clk);
            load_index = bank;
            top_down = (bank % 2 == 0);
            load_start = 1;
            @(negedge mem_clk); load_start = 0;
            for (k=0; k<WORDS; k=k+1) begin
                offset = top_down ? k : (479-k/640)*640 + k%640;
                pixel_rgb = pattern(bank, offset);
                pixel_valid = 1;
                @(negedge mem_clk); pixel_valid = 0;
                repeat (2) @(negedge mem_clk);
                // Bursty BMP replay, then an SD sector transfer interval.
                if (k%170==169) repeat (768) @(negedge mem_clk);
            end
            frame_commit = 1;
            @(negedge mem_clk); frame_commit = 0;
            wait(load_done);
            $display("bank %0d committed at %0t",bank,$time);
        end
    endtask

    task automatic pulse_next;
        begin
            @(negedge pix_clk); next_event = 1;
            @(negedge pix_clk); next_event = 0;
        end
    endtask

    task automatic publish_event;
        begin
            repeat(2) begin
                @(negedge pix_clk);trigger_event=1;
                @(negedge pix_clk);trigger_event=0;
            end
        end
    endtask
    task automatic clear_alert;
        begin
            repeat(2) begin
                @(negedge pix_clk);clear_event=1;
                @(negedge pix_clk);clear_event=0;
            end
        end
    endtask
    task automatic select_next_event;
        begin
            @(negedge pix_clk);clear_event=1;
            @(negedge pix_clk);clear_event=0;
        end
    endtask

    initial begin
        #201 rst_n = 1;
        load_image(0);
        fork
            begin
                load_image(2); load_image(3); load_image(4); load_image(5); load_image(1);
                all_loaded_time = $time;
            end
            begin
                wait(complete[2]);
                publish_event();
                wait(active_index==2); repeat(2)@(posedge frame_start);
                wait(complete[3]);
                clear_alert();select_next_event();publish_event();
                wait(active_index==3); repeat(2)@(posedge frame_start);
                wait(complete[4]);
                clear_alert();select_next_event();publish_event();
                wait(active_index==4); repeat(2)@(posedge frame_start);
                wait(complete[5]);
                clear_alert();select_next_event();publish_event();
                wait(active_index==5); repeat(2)@(posedge frame_start);
                wait(complete[1]);
                clear_alert();
                pulse_next(); wait(active_index==1);repeat(2)@(posedge frame_start);
            end
        join
        if (!first_display_time || first_display_time >= all_loaded_time ||
            background_reads==0 || displayed_frames<4 || writes!=WORDS*6 ||
            overlapping_grants==0) $fatal(1,"incomplete test coverage");
        $display("PASS progressive loading: first_pixel=%0d ns all_loaded=%0d ns frames=%0d pixels=%0d background_reads=%0d priority_contests=%0d",first_display_time,all_loaded_time,displayed_frames,checked_pixels,background_reads,overlapping_grants);
        $finish;
    end
    initial begin #500000000; $fatal(1,"simulation timeout"); end
endmodule
