`timescale 1ns/1ps
// Three explicitly supported 4:3 sizes. Input bytes must be >= 16 clocks apart
// (the sector replay buffer enforces this). Two source lines overlap capture
// with nearest-neighbour resampling; only normalized 640x480 pixels leave here.
module bmp_scale_decoder (
    input wire clk, rst_n, file_start,
    input wire [31:0] file_size,
    input wire file_valid,
    input wire [7:0] file_byte,
    input wire [31:0] file_byte_offset,
    input wire file_end,
    input wire [7:0] upstream_error,
    output reg header_accepted, pixel_valid,
    output reg [23:0] pixel_rgb,
    output reg [15:0] pixel_x, pixel_y,
    output reg frame_commit, bmp_done,
    output reg [7:0] bmp_error,
    output reg top_down,
    output reg [31:0] pixel_offset, row_stride
);
    reg [7:0] header [0:53];
    function [15:0] le16;
        input integer p;
        begin le16 = {header[p+1],header[p]}; end
    endfunction
    function [31:0] le32;
        input integer p;
        begin le32 = {header[p+3],header[p+2],header[p+1],header[p]}; end
    endfunction
    reg enabled, ended, finished;
    reg [1:0] scale_mode;
    reg [9:0] width, height, in_x, in_y;
    reg [2:0] row_mod5;
    reg [1:0] channel;
    reg [7:0] blue, green;
    reg capture_bank, render_bank, rendering, phase, repeat_row;
    reg [9:0] out_x, out_y;
    reg [18:0] output_count;
    reg [23:0] lines [0:2047];
    reg [23:0] line_q;
    wire [9:0] source_x = scale_mode == 0 ? (out_x >> 1) :
                                scale_mode == 2 ? out_x + (out_x >> 2) : out_x;
    wire [10:0] read_address = {render_bank,source_x};
    wire [10:0] write_address = {capture_bank,in_x};
    wire pixel_byte = enabled && file_valid && file_byte_offset >= pixel_offset && in_y < height;
    always @(posedge clk) begin
        if (pixel_byte && channel == 2) lines[write_address] <= {file_byte,green,blue};
        if (rendering && !phase) line_q <= lines[read_address];
    end
    reg [31:0] h_abs;
    reg [32:0] required_end;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled <= 0; ended <= 0; finished <= 0; header_accepted <= 0;
            pixel_valid <= 0; pixel_rgb <= 0; pixel_x <= 0; pixel_y <= 0;
            frame_commit <= 0; bmp_done <= 0; bmp_error <= 0; top_down <= 0;
            pixel_offset <= 0; row_stride <= 0; scale_mode <= 1;
            width <= 640; height <= 480; in_x <= 0; in_y <= 0; row_mod5 <= 0;
            channel <= 0; blue <= 0; green <= 0; capture_bank <= 0;
            render_bank <= 0; rendering <= 0; phase <= 0; repeat_row <= 0;
            out_x <= 0; out_y <= 0; output_count <= 0;
        end else begin
            pixel_valid <= 0; frame_commit <= 0; bmp_done <= 0;
            if (file_start) begin
                enabled <= 0; ended <= 0; finished <= 0; header_accepted <= 0;
                bmp_error <= 0; top_down <= 0; in_x <= 0; in_y <= 0;
                row_mod5 <= 0; channel <= 0; capture_bank <= 0;
                rendering <= 0; phase <= 0; out_x <= 0; out_y <= 0; output_count <= 0;
            end else begin
                if (file_valid && file_byte_offset < 54) header[file_byte_offset[5:0]] <= file_byte;
                if (file_valid && file_byte_offset == 53) begin
                    h_abs = le32(22);
                    if (h_abs[31]) h_abs = ~h_abs + 1'b1;
                    required_end = {1'b0,le32(10)} +
                        (le32(18) == 320 ? 33'd230400 : le32(18) == 640 ? 33'd921600 : 33'd1440000);
                    if (header[0] != "B" || header[1] != "M") bmp_error <= 8'h31;
                    else if (le32(14) != 40 || !((le32(18)==320 && h_abs==240) ||
                        (le32(18)==640 && h_abs==480) || (le32(18)==800 && h_abs==600))) bmp_error <= 8'h32;
                    else if (le16(26) != 1) bmp_error <= 8'h33;
                    else if (le16(28) != 24) bmp_error <= 8'h34;
                    else if (le32(30) != 0) bmp_error <= 8'h35;
                    else if (le32(10)<54 || le32(10)>4096) bmp_error <= 8'h36;
                    else if (required_end > {1'b0,file_size} || {1'b0,le32(2)} < required_end || le32(2)>file_size) bmp_error <= 8'h37;
                    else begin
                        enabled <= 1; header_accepted <= 1; top_down <= header[25][7];
                        pixel_offset <= le32(10); width <= le32(18); height <= h_abs;
                        row_stride <= le32(18)==320 ? 960 : le32(18)==640 ? 1920 : 2400;
                        scale_mode <= le32(18)==320 ? 0 : le32(18)==640 ? 1 : 2;
                    end
                end
                if (pixel_byte && bmp_error == 0) begin
                    case (channel)
                        0: begin blue <= file_byte; channel <= 1; end
                        1: begin green <= file_byte; channel <= 2; end
                        2: begin
                            channel <= 0;
                            if (in_x == width-1) begin
                                in_x <= 0; in_y <= in_y + 1'b1; capture_bank <= ~capture_bank;
                                row_mod5 <= row_mod5==4 ? 0 : row_mod5+1'b1;
                                if (scale_mode != 2 || row_mod5 != 4) begin
                                    if (rendering) bmp_error <= 8'h39;
                                    else begin
                                        render_bank <= capture_bank; rendering <= 1;
                                        phase <= 0; out_x <= 0; repeat_row <= 0;
                                    end
                                end
                            end else in_x <= in_x+1'b1;
                        end
                        default: channel <= 0;
                    endcase
                end
                if (rendering) begin
                    phase <= ~phase;
                    if (phase) begin
                        pixel_valid <= bmp_error == 0; pixel_rgb <= line_q;
                        pixel_x <= {6'd0,out_x}; pixel_y <= {6'd0,out_y};
                        output_count <= output_count + 1'b1;
                        if (out_x == 639) begin
                            out_x <= 0; out_y <= out_y + 1'b1;
                            if (scale_mode==0 && !repeat_row) repeat_row <= 1;
                            else rendering <= 0;
                        end else out_x <= out_x + 1'b1;
                    end
                end
                if (upstream_error != 0 && !finished) begin bmp_error <= 8'h38; enabled <= 0; end
                if (file_end) ended <= 1;
                if (ended && !rendering && !finished) begin
                    finished <= 1; enabled <= 0; bmp_done <= 1;
                    if (bmp_error == 0) begin
                        if (output_count == 307200 && in_y == height && channel==0) frame_commit <= 1;
                        else bmp_error <= 8'h37;
                    end
                end
            end
        end
    end
endmodule
