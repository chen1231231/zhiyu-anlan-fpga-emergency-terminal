`timescale 1ns/1ps

module media_ingest_frontend #(
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
    output wire                  done,
    output wire [7:0]            ingest_error,
    output wire [7:0]            ingest_detail_error,
    output wire [2:0]            current_image,
    output wire [5:0]            resource_valid,
    output wire [5:0]            image_complete,
    output wire [5:0]            image_failed,
    output wire [23:0]           image_failure_codes,
    output wire [5:0]            image_crc_ok,
    output wire [5:0]            image_crc_failed,
    output wire [3:0] audio_resource_valid,
    output wire [3:0] audio_crc_ok,
    output wire [3:0] audio_crc_failed,
    output wire plan_valid,
    output wire plan_error,
    output wire [29:0] plan_data,
    input wire audio_file_start, audio_file_stop,
    input wire [1:0] audio_file_select,
    input wire audio_sector_admit,
    output wire audio_file_busy, audio_file_done, audio_file_valid,
    output wire [7:0] audio_file_byte, audio_file_error,
    output wire                  reader_req,
    output wire [31:0]           reader_lba,
    input  wire                  reader_busy,
    input  wire                  reader_valid,
    input  wire [7:0]            reader_byte,
    input  wire [8:0]            reader_byte_index,
    input  wire                  reader_done,
    input  wire [7:0]            reader_error,
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
    wire replay_busy;
    wire replay_valid;
    wire [7:0] replay_byte;
    wire [8:0] replay_byte_index;
    wire replay_done;
    wire [7:0] replay_error;
    wire ingest_sector_req;
    wire [31:0] ingest_sector_lba;
    wire ingest_busy;

    assign busy = ingest_busy || replay_busy;

    sd_sector_replay_buffer u_sector_replay (
        .clk(clk), .rst_n(rst_n),
        .sector_req(ingest_sector_req), .sector_lba(ingest_sector_lba),
        .sector_busy(replay_busy), .sector_valid(replay_valid),
        .sector_byte(replay_byte), .sector_byte_index(replay_byte_index),
        .sector_done(replay_done), .sector_error(replay_error),
        .reader_req(reader_req), .reader_lba(reader_lba),
        .reader_busy(reader_busy), .reader_valid(reader_valid),
        .reader_byte(reader_byte), .reader_byte_index(reader_byte_index),
        .reader_done(reader_done), .reader_error(reader_error)
    );

    media_ingest_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH), .FIFO_DEPTH(FIFO_DEPTH),
        .STALL_TIMEOUT(STALL_TIMEOUT),.VERIFY_RELEASE_CRC(VERIFY_RELEASE_CRC)
    ) u_ingest_pipeline (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(ingest_busy), .done(done),
        .ingest_error(ingest_error), .ingest_detail_error(ingest_detail_error),
        .current_image(current_image),
        .resource_valid(resource_valid), .image_complete(image_complete),
        .image_failed(image_failed), .image_failure_codes(image_failure_codes),
        .image_crc_ok(image_crc_ok),.image_crc_failed(image_crc_failed),
        .audio_resource_valid(audio_resource_valid),
        .audio_crc_ok(audio_crc_ok),.audio_crc_failed(audio_crc_failed),
        .plan_valid(plan_valid),.plan_error(plan_error),.plan_data(plan_data),
        .audio_file_start(audio_file_start),.audio_file_stop(audio_file_stop),
        .audio_file_select(audio_file_select),.audio_sector_admit(audio_sector_admit),
        .audio_file_busy(audio_file_busy),.audio_file_done(audio_file_done),
        .audio_file_valid(audio_file_valid),.audio_file_byte(audio_file_byte),.audio_file_error(audio_file_error),
        .sector_req(ingest_sector_req), .sector_lba(ingest_sector_lba),
        .sector_busy(replay_busy), .sector_valid(replay_valid),
        .sector_byte(replay_byte), .sector_byte_index(replay_byte_index),
        .sector_done(replay_done), .sector_error(replay_error),
        .controller_init_done(controller_init_done), .controller_busy(controller_busy),
        .refresh_active(refresh_active), .app_wr_en(app_wr_en),
        .burst_grant(burst_grant), .burst_request(burst_request),
        .burst_busy(burst_busy),
        .app_wr_addr(app_wr_addr), .app_wr_mask(app_wr_mask), .app_wr_data(app_wr_data)
    );
endmodule
