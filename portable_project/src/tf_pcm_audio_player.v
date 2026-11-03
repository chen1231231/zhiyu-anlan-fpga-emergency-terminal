`timescale 1ns/1ps

// The shared plan maps campus/drill hazards. Mall hazards without a matching
// recorded voice must retain the generic alarm, even when a plan is enabled.
module terminal_plan_audio_select(
    input wire [1:0] scene_mode,event_type,
    input wire plan_valid,
    input wire [7:0] audio_map,
    output wire [1:0] player_event_type
);
    wire [1:0] selected_audio=audio_map >> {event_type,1'b0};
    assign player_event_type=(scene_mode==2'd2 && event_type!=0) ? 2'd3 :
        plan_valid ? (selected_audio==0 ? 2'd3 : selected_audio-1'b1) : event_type;
endmodule

// Streams signed 8-bit/16 kHz mono PCM through a small CDC FIFO and emits
// 48 kHz/16-bit HDMI samples by repeating each source sample three times.
module tf_pcm_audio_player #(
    parameter integer PIXEL_CLOCK_HZ = 25000000,
    parameter integer OUTPUT_SAMPLE_HZ = 48000
) (
    input  wire               mem_clk,
    input  wire               mem_rst_n,
    input  wire               pix_clk,
    input  wire               pix_rst_n,
    input  wire               alarm_enable,
    input  wire               audio_test,
    input  wire [1:0]         event_type,
    input  wire [7:0]         volume,
    input  wire [3:0]         audio_available,

    output reg                file_start,
    output reg                file_stop,
    output reg  [1:0]         file_select,
    output wire               sector_admit,
    input  wire               file_busy,
    input  wire               file_done,
    input  wire               file_valid,
    input  wire [7:0]         file_byte,
    input  wire [7:0]         file_error,

    output reg                sample_valid,
    output reg signed [15:0]  sample_left,
    output wire signed [15:0] sample_right,
    output reg                underflow,
    output reg                pcm_starved,
    output reg  [7:0]         player_error
);
    reg enable_sync1_mem, enable_sync2_mem;
    reg [1:0] select_sync1_mem, select_sync2_mem;
    wire pix_reset_n_mem;
    reg active_mem, start_pending_mem, selected_available_q_mem;
    reg stream_failed_mem;
    reg [2:0] fifo_reset_count_mem;
    reg [1:0] pack_index_mem;
    reg [31:0] pack_word_mem;
    reg fifo_write_mem;
    reg [31:0] fifo_write_data_mem;

    wire enable_pix = alarm_enable || audio_test;
    wire [1:0] requested_select_pix = audio_test ? 2'd0 :
                                      event_type == 2'd0 ? 2'd1 :
                                      event_type == 2'd1 ? 2'd2 :
                                      event_type == 2'd2 ? 2'd3 : 2'd0;
    wire [1:0] available_select_mem = audio_available[select_sync2_mem] ?
                                      select_sync2_mem : 2'd0;
    wire selected_available_mem = audio_available[available_select_mem];
    wire fifo_reset = !mem_rst_n || !pix_reset_n_mem || fifo_reset_count_mem != 0;
    wire fifo_full, fifo_empty, fifo_almost_full;
    wire [8:0] fifo_wrusedw, fifo_rdusedw;
    wire [31:0] fifo_read_data;
    reg fifo_read_pix;

    assign sector_admit = active_mem && !fifo_reset && fifo_wrusedw <= 9'd380;
    assign sample_right = sample_left;

    sync_2ff u_pix_reset_to_mem (
        .clk(mem_clk), .rst_n(mem_rst_n),
        .async_in(pix_rst_n), .sync_out(pix_reset_n_mem)
    );

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            enable_sync1_mem <= 0; enable_sync2_mem <= 0;
            select_sync1_mem <= 0; select_sync2_mem <= 0;
            active_mem <= 0; start_pending_mem <= 0;
            selected_available_q_mem <= 0; stream_failed_mem <= 0;
            fifo_reset_count_mem <= 3'd4;
            pack_index_mem <= 0; pack_word_mem <= 0;
            fifo_write_mem <= 0; fifo_write_data_mem <= 0;
            file_start <= 0; file_stop <= 0; file_select <= 0;
            player_error <= 0;
        end else begin
            enable_sync1_mem <= enable_pix;
            enable_sync2_mem <= enable_sync1_mem;
            select_sync1_mem <= requested_select_pix;
            select_sync2_mem <= select_sync1_mem;
            file_start <= 0;
            file_stop <= 0;
            fifo_write_mem <= 0;
            if (fifo_reset_count_mem != 0)
                fifo_reset_count_mem <= fifo_reset_count_mem - 1'b1;

            if (!enable_sync2_mem) begin
                if (active_mem || file_busy) file_stop <= 1'b1;
                active_mem <= 0;
                start_pending_mem <= 0;
                selected_available_q_mem <= 0;
                stream_failed_mem <= 0;
                pack_index_mem <= 0;
                fifo_reset_count_mem <= 3'd4;
                player_error <= 0;
            end else if (!active_mem || file_select != available_select_mem) begin
                if (active_mem || file_busy) file_stop <= 1'b1;
                active_mem <= 1'b1;
                file_select <= available_select_mem;
                start_pending_mem <= selected_available_mem;
                selected_available_q_mem <= selected_available_mem;
                stream_failed_mem <= 0;
                pack_index_mem <= 0;
                fifo_reset_count_mem <= 3'd4;
                player_error <= selected_available_mem ? 8'd0 : 8'h71;
            end else begin
                selected_available_q_mem <= selected_available_mem;
                if (!selected_available_q_mem && selected_available_mem) begin
                    start_pending_mem <= 1'b1;
                    stream_failed_mem <= 1'b0;
                    fifo_reset_count_mem <= 3'd4;
                    player_error <= 8'd0;
                end
                if (start_pending_mem && !stream_failed_mem && !file_busy &&
                    fifo_reset_count_mem == 0) begin
                    file_start <= 1'b1;
                    start_pending_mem <= 1'b0;
                end
                if (file_done) begin
                    if (file_error != 0) begin
                        start_pending_mem <= 1'b0;
                        stream_failed_mem <= 1'b1;
                        player_error <= file_error;
                    end else begin
                        start_pending_mem <= 1'b1;
                    end
                end

                if (file_valid && !fifo_reset) begin
                    case (pack_index_mem)
                        2'd0: begin pack_word_mem <= {24'd0,file_byte}; pack_index_mem <= 2'd1; end
                        2'd1: begin pack_word_mem[15:8] <= file_byte; pack_index_mem <= 2'd2; end
                        2'd2: begin pack_word_mem[23:16] <= file_byte; pack_index_mem <= 2'd3; end
                        default: begin
                            fifo_write_data_mem <= {file_byte,pack_word_mem[23:0]};
                            fifo_write_mem <= 1'b1;
                            pack_index_mem <= 2'd0;
                        end
                    endcase
                end else if (file_done && pack_index_mem != 0 && !fifo_reset) begin
                    fifo_write_data_mem <= pack_word_mem;
                    fifo_write_mem <= 1'b1;
                    pack_index_mem <= 0;
                end
                if (fifo_write_mem && fifo_full) player_error <= 8'h72;
            end
        end
    end

    rfifo_32_32_512 #(
        .DATA_WIDTH_W(32), .DATA_WIDTH_R(32),
        .ADDR_WIDTH_W(9), .ADDR_WIDTH_R(9),
        .AL_FULL_NUM(380), .AL_EMPTY_NUM(64),
        .SHOW_AHEAD_EN(1'b1), .OUTREG_EN("NOREG")
    ) u_audio_fifo (
        .rst(fifo_reset), .clkw(mem_clk), .clkr(pix_clk),
        .we(fifo_write_mem && !fifo_full), .di(fifo_write_data_mem),
        .re(fifo_read_pix), .dout(fifo_read_data), .valid(),
        .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(fifo_almost_full), .aempty(),
        .wrusedw(fifo_wrusedw), .rdusedw(fifo_rdusedw)
    );

    reg [24:0] sample_accumulator_pix;
    reg [1:0] repeat_count_pix;
    reg [1:0] byte_index_pix;
    reg playback_armed_pix;
    reg fifo_reset_sync1_pix, fifo_reset_sync2_pix;
    wire fifo_hold_pix = fifo_reset_sync2_pix;
    wire sample_tick_pix = sample_accumulator_pix >= PIXEL_CLOCK_HZ - OUTPUT_SAMPLE_HZ;
    wire signed [7:0] pcm8_pix = byte_index_pix == 0 ? fifo_read_data[7:0] :
                                 byte_index_pix == 1 ? fifo_read_data[15:8] :
                                 byte_index_pix == 2 ? fifo_read_data[23:16] :
                                                       fifo_read_data[31:24];
    wire signed [15:0] pcm16_pix = {pcm8_pix,8'd0};
    wire signed [23:0] scaled_pix = pcm16_pix * $signed({1'b0,volume});
    wire signed [15:0] volume_sample_pix = scaled_pix >>> 8;

    // The FIFO handles asynchronous assertion and synchronous release itself.
    // This synchronizer gives the surrounding playback state the same clean release.
    always @(posedge pix_clk or posedge fifo_reset) begin
        if (fifo_reset) begin
            fifo_reset_sync1_pix <= 1'b1;
            fifo_reset_sync2_pix <= 1'b1;
        end else begin
            fifo_reset_sync1_pix <= 1'b0;
            fifo_reset_sync2_pix <= fifo_reset_sync1_pix;
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            sample_accumulator_pix <= 0;
            repeat_count_pix <= 0;
            byte_index_pix <= 0;
            playback_armed_pix <= 0;
            fifo_read_pix <= 0;
            sample_valid <= 0;
            sample_left <= 0;
            underflow <= 0;
            pcm_starved <= 1;
        end else begin
            fifo_read_pix <= 0;
            sample_valid <= 0;
            if (sample_tick_pix)
                sample_accumulator_pix <= sample_accumulator_pix + OUTPUT_SAMPLE_HZ - PIXEL_CLOCK_HZ;
            else
                sample_accumulator_pix <= sample_accumulator_pix + OUTPUT_SAMPLE_HZ;

            if (!enable_pix || fifo_hold_pix) begin
                repeat_count_pix <= 0;
                byte_index_pix <= 0;
                playback_armed_pix <= 0;
                sample_left <= 0;
                underflow <= 0;
            end else if (!playback_armed_pix && fifo_rdusedw >= 9'd64) begin
                playback_armed_pix <= 1'b1;
            end

            if (sample_tick_pix) begin
                sample_valid <= 1'b1;
                pcm_starved <= !(enable_pix && playback_armed_pix && !fifo_empty);
                if (enable_pix && playback_armed_pix && !fifo_empty) begin
                    sample_left <= volume_sample_pix;
                    if (repeat_count_pix == 2) begin
                        repeat_count_pix <= 0;
                        if (byte_index_pix == 3) begin
                            byte_index_pix <= 0;
                            fifo_read_pix <= 1'b1;
                        end else begin
                            byte_index_pix <= byte_index_pix + 1'b1;
                        end
                    end else begin
                        repeat_count_pix <= repeat_count_pix + 1'b1;
                    end
                end else begin
                    sample_left <= 0;
                    if (enable_pix && playback_armed_pix) underflow <= 1'b1;
                end
            end
        end
    end
endmodule
