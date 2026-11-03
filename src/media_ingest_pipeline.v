`timescale 1ns/1ps

module media_ingest_pipeline #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer IMAGE_HEIGHT = 480,
    parameter integer ADDR_WIDTH = 21,
    parameter integer FIFO_DEPTH = 2048,
    parameter integer STALL_TIMEOUT = 65535,
    parameter integer VERIFY_RELEASE_CRC = 0
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    output wire                  busy,
    output reg                   done,
    output reg  [7:0]            ingest_error,
    output reg  [7:0]            ingest_detail_error,
    output reg  [2:0]            current_image,
    output wire [5:0]            resource_valid,
    output wire [5:0]            image_complete,
    output reg [5:0]             image_failed,
    output reg [23:0]            image_failure_codes,
    output reg [5:0]             image_crc_ok,
    output reg [5:0]             image_crc_failed,
    output wire [3:0] audio_resource_valid,
    output reg [3:0] audio_crc_ok,
    output reg [3:0] audio_crc_failed,
    output reg plan_valid,
    output reg plan_error,
    output reg [29:0] plan_data,
    input wire audio_file_start, audio_file_stop,
    input wire [1:0] audio_file_select,
    input wire audio_sector_admit,
    output wire audio_file_busy, audio_file_done, audio_file_valid,
    output wire [7:0] audio_file_byte, audio_file_error,

    output wire                  sector_req,
    output wire [31:0]           sector_lba,
    input  wire                  sector_busy,
    input  wire                  sector_valid,
    input  wire [7:0]            sector_byte,
    input  wire [8:0]            sector_byte_index,
    input  wire                  sector_done,
    input  wire [7:0]            sector_error,

    input  wire                  controller_init_done,
    input  wire                  controller_busy,
    input  wire                  refresh_active,
    input  wire                  burst_grant,
    output wire                  burst_request,
    output wire                  burst_busy,
    output wire                  app_wr_en,
    output wire [ADDR_WIDTH-1:0] app_wr_addr,
    output wire [3:0]            app_wr_mask,
    output wire [31:0]           app_wr_data
);
    localparam integer IMAGE_WORDS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam ERR_NONE   = 8'h00;
    localparam ERR_SCAN   = 8'h80;
    localparam ERR_FILE   = 8'h82;
    localparam ERR_BMP    = 8'h83;
    localparam ERR_MEMORY = 8'h84;

    localparam ST_IDLE       = 4'd0;
    localparam ST_SCAN       = 4'd1;
    localparam ST_PLAN_START = 4'd2;
    localparam ST_PLAN_FILE  = 4'd3;
    localparam ST_FILE_START = 4'd4;
    localparam ST_FILE       = 4'd5;
    localparam ST_FAIL_WAIT  = 4'd6;
    localparam ST_NEXT       = 4'd7;

    reg [3:0] state;
    reg scan_start;
    reg file_start;
    reg load_start;
    reg file_finished, load_finished;
    reg [2:0] load_step;
    reg image_retry;
    reg [7:0] image_crc,audio_crc;
    reg [1:0] audio_crc_select;
    reg [7:0] plan_crc;
    reg plan_header_ok;

    // One-level XOR8 is the on-device content signature. Strong SHA-256 and
    // ZIP CRC32 remain part of release packaging; the FPGA also checks size,
    // BMP structure, complete decoding and complete SDRAM writes.
    function [7:0] crc8_byte;
        input [7:0] crc_in,data;
        begin
            crc8_byte=crc_in^data;
        end
    endfunction
    function [7:0] expected_image_crc;
        input [2:0] index;
        begin case(index)
            0:expected_image_crc=8'hb4; 1:expected_image_crc=8'h29;
            2:expected_image_crc=8'h79; 3:expected_image_crc=8'h78;
            4:expected_image_crc=8'h1d; default:expected_image_crc=8'hb6;
        endcase end
    endfunction
    function [7:0] expected_audio_crc;
        input [1:0] index;
        begin case(index)
            0:expected_audio_crc=8'hb5; 1:expected_audio_crc=8'h4a;
            2:expected_audio_crc=8'h0a; default:expected_audio_crc=8'hfe;
        endcase end
    endfunction

    wire scan_busy;
    wire scan_done;
    wire [7:0] scan_error;
    wire [7:0] sectors_per_cluster;
    wire [31:0] fat_start_lba;
    wire [31:0] data_start_lba;
    wire [31:0] max_cluster;
    wire [31:0] resource0_cluster, resource1_cluster;
    wire [31:0] resource2_cluster, resource3_cluster;
    wire [31:0] resource4_cluster, resource5_cluster;
    wire [31:0] resource0_size, resource1_size;
    wire [31:0] resource2_size, resource3_size;
    wire [31:0] resource4_size, resource5_size;
    wire plan_resource_valid;
    wire [31:0] plan_cluster,plan_size;
    wire scan_sector_req;
    wire [31:0] scan_sector_lba;

    wire file_busy;
    wire file_done;
    wire file_valid;
    wire [7:0] file_byte;
    wire [31:0] file_byte_offset;
    wire [7:0] file_error;
    wire file_sector_req;
    wire [31:0] file_sector_lba;
    wire [31:0] selected_cluster;
    wire [31:0] selected_size;

    wire pixel_valid;
    wire [23:0] pixel_rgb;
    wire frame_commit;
    wire bmp_done;
    wire [7:0] bmp_error;
    wire load_busy;
    wire load_done;
    wire [7:0] memory_error;
    wire loader_input_ready;

    assign busy = state != ST_IDLE;
    wire image_sector_busy, image_sector_valid, image_sector_done;
    wire audio_sector_req, audio_sector_busy, audio_sector_valid, audio_sector_done;
    wire [31:0] audio_sector_lba;
    wire audio_stream_busy;
    wire [31:0] audio0_cluster,audio1_cluster,audio2_cluster,audio3_cluster;
    wire [31:0] audio0_size,audio1_size,audio2_size,audio3_size;
    wire [31:0] audio_cluster = audio_file_select==0 ? audio0_cluster :
        audio_file_select==1 ? audio1_cluster : audio_file_select==2 ? audio2_cluster : audio3_cluster;
    wire [31:0] audio_size = audio_file_select==0 ? audio0_size :
        audio_file_select==1 ? audio1_size : audio_file_select==2 ? audio2_size : audio3_size;
    // Keep the player from restarting while a stopped stream's admitted
    // sector is draining. This prevents old-event bytes entering the new FIFO.
    reg audio_transaction;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) audio_transaction<=0;
        else if(audio_sector_req) audio_transaction<=1;
        else if(audio_sector_done) audio_transaction<=0;
    end
    assign audio_file_busy = audio_stream_busy || audio_transaction || audio_sector_req;
    // The sector arbiter routes a byte to either the image reader or the audio
    // reader, never both. Share one CRC update network to fit the small FPGA.
    wire [7:0] crc_update_base=file_valid ? image_crc:audio_crc;
    wire [7:0] crc_update_data=file_valid ? file_byte:audio_file_byte;
    wire [7:0] crc_update_value=crc8_byte(crc_update_base,crc_update_data);
    wire [7:0] image_crc_result=image_crc;
    wire image_crc_mismatch=VERIFY_RELEASE_CRC && (file_finished || file_done) &&
        image_crc_result!=expected_image_crc(current_image);

    media_sector_arbiter u_sector_arbiter (
        .clk(clk),.rst_n(rst_n),
        .image_req(scan_sector_req | file_sector_req),
        .image_lba(scan_sector_req ? scan_sector_lba : file_sector_lba),
        .image_busy(image_sector_busy),.image_valid(image_sector_valid),.image_done(image_sector_done),
        .audio_req(audio_sector_req),.audio_lba(audio_sector_lba),
        .audio_busy(audio_sector_busy),.audio_valid(audio_sector_valid),.audio_done(audio_sector_done),
        .sector_req(sector_req),.sector_lba(sector_lba),
        .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_done(sector_done)
    );
    fat32_audio_streamer u_audio_streamer (
        .clk(clk),.rst_n(rst_n),.file_start(audio_file_start),.file_stop(audio_file_stop),
        .sector_admit(audio_sector_admit),.first_cluster(audio_cluster),.file_size(audio_size),
        .sectors_per_cluster(sectors_per_cluster),.fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),.max_cluster(max_cluster),
        .file_busy(audio_stream_busy),.file_done(audio_file_done),.file_valid(audio_file_valid),
        .file_byte(audio_file_byte),.fs_error(audio_file_error),
        .sector_req(audio_sector_req),.sector_lba(audio_sector_lba),
        .sector_busy(audio_sector_busy),.sector_valid(audio_sector_valid),
        .sector_byte(sector_byte),.sector_byte_index(sector_byte_index),
        .sector_done(audio_sector_done),.sector_error(sector_error)
    );

    wire loading_plan = state == ST_PLAN_START || state == ST_PLAN_FILE;
    assign selected_cluster = loading_plan ? plan_cluster :
                              current_image == 2'd0 ? resource0_cluster :
                              current_image == 2'd1 ? resource1_cluster :
                              current_image == 3'd2 ? resource2_cluster :
                              current_image == 3'd3 ? resource3_cluster :
                              current_image == 3'd4 ? resource4_cluster : resource5_cluster;
    assign selected_size = loading_plan ? plan_size :
                           current_image == 2'd0 ? resource0_size :
                           current_image == 2'd1 ? resource1_size :
                           current_image == 3'd2 ? resource2_size :
                           current_image == 3'd3 ? resource3_size :
                           current_image == 3'd4 ? resource4_size : resource5_size;

    fat32_volume_scanner u_volume_scanner (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start), .scan_busy(scan_busy),
        .scan_done(scan_done), .fs_error(scan_error), .partition_lba(),
        .sectors_per_cluster(sectors_per_cluster), .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba), .max_cluster(max_cluster),
        .resource_valid(resource_valid),
        .audio_resource_valid(audio_resource_valid),
        .audio0_cluster(audio0_cluster),.audio1_cluster(audio1_cluster),
        .audio2_cluster(audio2_cluster),.audio3_cluster(audio3_cluster),
        .audio0_size(audio0_size),.audio1_size(audio1_size),.audio2_size(audio2_size),.audio3_size(audio3_size),
        .plan_resource_valid(plan_resource_valid),.plan_cluster(plan_cluster),.plan_size(plan_size),
        .resource0_cluster(resource0_cluster), .resource1_cluster(resource1_cluster),
        .resource2_cluster(resource2_cluster), .resource3_cluster(resource3_cluster),
        .resource4_cluster(resource4_cluster), .resource5_cluster(resource5_cluster),
        .resource0_size(resource0_size), .resource1_size(resource1_size),
        .resource2_size(resource2_size), .resource3_size(resource3_size),
        .resource4_size(resource4_size), .resource5_size(resource5_size),
        .sector_req(scan_sector_req), .sector_lba(scan_sector_lba),
        .sector_busy(image_sector_busy), .sector_valid(image_sector_valid), .sector_byte(sector_byte),
        .sector_byte_index(sector_byte_index), .sector_done(image_sector_done),
        .sector_error(sector_error)
    );

    fat32_file_streamer u_file_streamer (
        .clk(clk), .rst_n(rst_n), .file_start(file_start),
        .first_cluster(selected_cluster), .file_size(selected_size),
        .sectors_per_cluster(sectors_per_cluster), .fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba), .max_cluster(max_cluster),
        .file_busy(file_busy), .file_done(file_done), .file_valid(file_valid),
        .file_byte(file_byte), .file_byte_offset(file_byte_offset), .fs_error(file_error),
        .sector_req(file_sector_req), .sector_lba(file_sector_lba),
        .sector_busy(image_sector_busy || (!loading_plan && !loader_input_ready)), .sector_valid(image_sector_valid), .sector_byte(sector_byte),
        .sector_byte_index(sector_byte_index), .sector_done(image_sector_done),
        .sector_error(sector_error)
    );

    wire top_down_w;
    bmp_scale_decoder u_bmp_decoder (
        .clk(clk), .rst_n(rst_n), .file_start(file_start && !loading_plan), .file_size(selected_size),
        .file_valid(file_valid && !loading_plan), .file_byte(file_byte), .file_byte_offset(file_byte_offset),
        .file_end(file_done && !loading_plan), .upstream_error(file_error), .header_accepted(),
        .pixel_valid(pixel_valid), .pixel_rgb(pixel_rgb), .pixel_x(), .pixel_y(),
        .frame_commit(frame_commit), .bmp_done(bmp_done), .bmp_error(bmp_error),
        .top_down(top_down_w), .pixel_offset(), .row_stride()
    );

    media_frame_loader #(
        .ADDR_WIDTH(ADDR_WIDTH), .IMAGE_WORDS(IMAGE_WORDS),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH), .STALL_TIMEOUT(STALL_TIMEOUT)
    ) u_frame_loader (
        .clk(clk), .rst_n(rst_n), .load_start(load_start), .image_index(current_image),
        .pixel_valid(pixel_valid), .pixel_rgb(pixel_rgb),
        .top_down(top_down_w), .frame_commit(frame_commit),
        .decode_error(bmp_error), .load_busy(load_busy), .load_done(load_done),
        .input_ready(loader_input_ready),
        .image_complete(image_complete), .memory_error(memory_error),
        .controller_init_done(controller_init_done), .controller_busy(controller_busy),
        .refresh_active(refresh_active), .app_wr_en(app_wr_en),
        .burst_grant(burst_grant), .burst_request(burst_request),
        .burst_busy(burst_busy),
        .app_wr_addr(app_wr_addr), .app_wr_mask(app_wr_mask), .app_wr_data(app_wr_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            file_finished <= 0; load_finished <= 0; load_step <= 0;
            scan_start <= 1'b0;
            file_start <= 1'b0;
            load_start <= 1'b0;
            done <= 1'b0;
            ingest_error <= ERR_NONE;
            ingest_detail_error <= ERR_NONE;
            current_image <= 3'd0; load_step <= 0;
            image_failed <= 0; image_failure_codes <= 0; image_retry <= 0;
            image_crc<=0;image_crc_ok<=0;image_crc_failed<=0;
            audio_crc<=0;audio_crc_select<=0;audio_crc_ok<=0;audio_crc_failed<=0;
            plan_valid<=0;plan_error<=0;plan_data<=0;plan_crc<=0;plan_header_ok<=0;
        end else begin
            scan_start <= 1'b0;
            file_start <= 1'b0;
            load_start <= 1'b0;
            done <= 1'b0;
            if(audio_file_start) begin audio_crc<=0;audio_crc_select<=audio_file_select;end
            else if(audio_file_valid) audio_crc<=crc_update_value;
            if(audio_file_done && VERIFY_RELEASE_CRC) begin
                if(audio_crc==expected_audio_crc(audio_crc_select)) audio_crc_ok[audio_crc_select]<=1;
                else audio_crc_failed[audio_crc_select]<=1;
            end

            case (state)
                ST_IDLE: if (start) begin
                    ingest_error <= ERR_NONE;
                    ingest_detail_error <= ERR_NONE;
                    current_image <= 3'd0; load_step <= 0;
                    image_failed <= 0; image_failure_codes <= 0; image_retry <= 0;
                    // Verified frames remain in SDRAM across card rescans.
                    // Preserve their signatures and never overwrite a visible
                    // bank; a reset is required to replace approved assets.
                    image_crc_failed<=0;audio_crc_ok<=0;audio_crc_failed<=0;
                    plan_valid<=0;plan_error<=0;
                    scan_start <= 1'b1;
                    state <= ST_SCAN;
                end
                ST_SCAN: if (scan_done) begin
                    if (scan_error != 0 && scan_error != 8'h22) begin
                        ingest_error <= ERR_SCAN;
                        ingest_detail_error <= scan_error;
                        image_failed <= 6'h3f;
                        image_failure_codes <= {6{4'd5}};
                        state <= ST_FAIL_WAIT;
                    end else begin
                        current_image <= 3'd0; load_step <= 0;
                        if(!plan_resource_valid) begin plan_valid<=0;plan_data<=0;end
                        state <= plan_resource_valid ? ST_PLAN_START : ST_FILE_START;
                    end
                end
                ST_PLAN_START: begin
                    plan_crc<=0; plan_header_ok<=1;
                    plan_valid<=0;
                    file_start<=1; state<=ST_PLAN_FILE;
                end
                ST_PLAN_FILE: begin
                    if(file_valid) begin
                        plan_crc<=plan_crc^file_byte;
                        // PLAN.BIN is exactly 24 bytes, so only five offset
                        // bits are needed. Avoid a 32-bit 16-way decoder.
                        case(file_byte_offset[4:0])
                            0: if(file_byte!="E") plan_header_ok<=0;
                            1: if(file_byte!="P") plan_header_ok<=0;
                            2: if(file_byte!="L") plan_header_ok<=0;
                            3: if(file_byte!="N") plan_header_ok<=0;
                            4: if(file_byte!=1) plan_header_ok<=0;
                            5: if(!file_byte[0]) plan_header_ok<=0;
                            6: begin plan_data[4:0]<=file_byte[4:0]; if(file_byte<3||file_byte>30) plan_header_ok<=0; end
                            7: begin plan_data[8:5]<=file_byte[3:0]; if(file_byte<2||file_byte>15) plan_header_ok<=0; end
                            8: begin plan_data[11:9]<=file_byte[2:0]; if(file_byte>4) plan_header_ok<=0; end
                            9: begin plan_data[13:12]<=file_byte[1:0]; if(file_byte>2) plan_header_ok<=0; end
                            10: plan_data[21:14]<=file_byte;
                            11: plan_data[29:22]<=file_byte;
                            12,13,14,15,16,17,18,19,20,21,22:
                                if(file_byte!=0) plan_header_ok<=0;
                            default: ;
                        endcase
                    end
                    if(file_done) begin
                        if(file_error!=0) plan_error<=1;
                        else if(plan_size!=24 || !plan_header_ok || plan_crc!=0) plan_error<=1;
                        else plan_valid<=1;
                        state<=ST_FILE_START;
                    end
                end
                ST_FILE_START: begin
                    file_finished <= 0; load_finished <= 0;
                    if (VERIFY_RELEASE_CRC && image_crc_ok[current_image] && image_complete[current_image]) begin
                        // A previous attempt already committed this complete
                        // bank. Skip file reads and all writes during recovery.
                        state <= ST_NEXT;
                    end else if (!resource_valid[current_image]) begin
                        ingest_error <= ERR_SCAN; ingest_detail_error <= 8'h22;
                        image_failed[current_image] <= 1;
                        image_failure_codes[current_image*4 +: 4] <= 4'd1;
                        state <= ST_NEXT;
                    end else begin
                        image_crc<=0;
                        file_start <= 1; load_start <= 1; state <= ST_FILE;
                    end
                end
                ST_FILE: begin
                    if(file_valid) image_crc<=crc_update_value;
                    if (file_done) file_finished <= 1;
                    if (load_done) load_finished <= 1;
                    if ((file_finished || file_done) && (load_finished || load_done)) begin
                        if (file_error != 0 || bmp_error != 0 || memory_error != 0 || image_crc_mismatch) begin
                            if (!image_retry && (file_error == 8'h10 ||
                                memory_error == 8'h42 || memory_error == 8'h46)) begin
                                // A transient sector or SDRAM admission failure
                                // must not permanently discard an otherwise valid page.
                                image_retry <= 1;
                                state <= ST_FILE_START;
                            end else begin
                                ingest_error <= file_error != 0 ? ERR_FILE :
                                                bmp_error != 0 ? ERR_BMP :
                                                memory_error != 0 ? ERR_MEMORY : 8'h85;
                                ingest_detail_error <= file_error != 0 ? file_error :
                                                       bmp_error != 0 ? bmp_error :
                                                       memory_error != 0 ? memory_error : 8'h01;
                                image_failed[current_image] <= 1;
                                image_failure_codes[current_image*4 +: 4] <=
                                    file_error != 0 ? 4'd2 : bmp_error != 0 ? 4'd3 :
                                    memory_error != 0 ? 4'd4 : 4'd6;
                                if(image_crc_mismatch) image_crc_failed[current_image]<=1;
                                state <= ST_NEXT;
                            end
                        end else begin
                            if(VERIFY_RELEASE_CRC) image_crc_ok[current_image]<=1;
                            state <= ST_NEXT;
                        end
                    end
                end
                ST_NEXT: begin
                    image_retry <= 0;
                    // Commit NORMAL and SAFETY first, then load emergency pages.
                    if (load_step == 5) begin done <= 1; state <= ST_IDLE; end
                    else begin
                        load_step <= load_step + 1'b1;
                        case (load_step)
                            0: current_image <= 1;
                            1: current_image <= 2;
                            2: current_image <= 3;
                            3: current_image <= 4;
                            default: current_image <= 5;
                        endcase
                        state <= ST_FILE_START;
                    end
                end
                ST_FAIL_WAIT: if (!scan_busy && !file_busy && !load_busy) begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
