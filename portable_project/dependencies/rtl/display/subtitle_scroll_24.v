`timescale 1ns/1ps

// Bottom scrolling subtitle banner: "米醋电子工作室忧郁", one 12x12 glyph row
// stepping left by SCROLL_STEP pixels per frame and wrapping around. E1
// extension: layered overlay with smooth scrolling. Every output (RGB and all
// video timing signals consumed downstream) is delayed by the same single
// clock, so DE/X/sync alignment is preserved when chained after other overlay
// stages.
module subtitle_scroll_24 #(
    parameter integer SUB_Y = 438,
    parameter integer SCROLL_STEP = 2,
    parameter integer H_ACT = 640,
    parameter [23:0] TEXT_COLOR = 24'hFFD966
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hsync,
    input  wire        vsync,
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [23:0] rgb_in,
    output reg         hsync_out,
    output reg         vsync_out,
    output reg         de_out,
    output reg  [9:0]  pixel_x_out,
    output wire [23:0] rgb_out,
    output wire        subtitle_active
);
    localparam integer GLYPH_W = 12;
    localparam integer GLYPH_H = 12;
    localparam integer GLYPH_STRIDE = 16;
    localparam integer GLYPH_COUNT = 9;
    localparam integer TEXT_W = GLYPH_STRIDE * GLYPH_COUNT;
    localparam integer SPAN = H_ACT + TEXT_W;
    localparam [9:0] H_ACT_R = H_ACT;
    localparam [11:0] SUB_Y_R = SUB_Y;
    localparam [11:0] GLYPH_H_R = GLYPH_H;
    localparam [10:0] TEXT_W_R = TEXT_W;
    localparam [10:0] SPAN_R = SPAN;
    localparam [10:0] STEP_R = SCROLL_STEP;
    localparam [3:0] SUB_Y_ROW = SUB_Y % 16;

    reg [11:0] glyph_rom [0:143] /* fehdl force_ram=1, ram_style="bram" */;
    integer init_index;
    initial begin
        for (init_index = 0; init_index < 144; init_index = init_index + 1)
            glyph_rom[init_index] = 12'h000;

        // 米 U+7C73
        glyph_rom[0]=12'h060; glyph_rom[1]=12'h224;
        glyph_rom[2]=12'h128; glyph_rom[3]=12'h128;
        glyph_rom[4]=12'h020; glyph_rom[5]=12'h7FE;
        glyph_rom[6]=12'h0B0; glyph_rom[7]=12'h1A8;
        glyph_rom[8]=12'h326; glyph_rom[9]=12'h622;
        glyph_rom[10]=12'h020;

        // 醋 U+918B
        glyph_rom[12]=12'h014; glyph_rom[13]=12'hFD4;
        glyph_rom[14]=12'h31E; glyph_rom[15]=12'h7D4;
        glyph_rom[16]=12'h77F; glyph_rom[17]=12'h740;
        glyph_rom[18]=12'h7DE; glyph_rom[19]=12'h462;
        glyph_rom[20]=12'h7DE; glyph_rom[21]=12'h462;
        glyph_rom[22]=12'h7FE;

        // 电 U+7535
        glyph_rom[24]=12'h040; glyph_rom[25]=12'h040;
        glyph_rom[26]=12'h7FC; glyph_rom[27]=12'h444;
        glyph_rom[28]=12'h444; glyph_rom[29]=12'h7FC;
        glyph_rom[30]=12'h444; glyph_rom[31]=12'h7FC;
        glyph_rom[32]=12'h440; glyph_rom[33]=12'h042;
        glyph_rom[34]=12'h07E;

        // 子 U+5B50
        glyph_rom[36]=12'h3FC; glyph_rom[37]=12'h018;
        glyph_rom[38]=12'h060; glyph_rom[39]=12'h040;
        glyph_rom[40]=12'h7FE; glyph_rom[41]=12'h040;
        glyph_rom[42]=12'h040; glyph_rom[43]=12'h040;
        glyph_rom[44]=12'h040; glyph_rom[45]=12'h0C0;

        // 工 U+5DE5
        glyph_rom[48]=12'h7FC; glyph_rom[49]=12'h040;
        glyph_rom[50]=12'h040; glyph_rom[51]=12'h040;
        glyph_rom[52]=12'h040; glyph_rom[53]=12'h040;
        glyph_rom[54]=12'h040; glyph_rom[55]=12'h040;
        glyph_rom[56]=12'h7FE;

        // 作 U+4F5C
        glyph_rom[60]=12'h130; glyph_rom[61]=12'h120;
        glyph_rom[62]=12'h27E; glyph_rom[63]=12'h250;
        glyph_rom[64]=12'h690; glyph_rom[65]=12'hE1E;
        glyph_rom[66]=12'h210; glyph_rom[67]=12'h210;
        glyph_rom[68]=12'h21E; glyph_rom[69]=12'h210;
        glyph_rom[70]=12'h210;

        // 室 U+5BA4
        glyph_rom[72]=12'h040; glyph_rom[73]=12'h060;
        glyph_rom[74]=12'h7FE; glyph_rom[75]=12'h402;
        glyph_rom[76]=12'h3FC; glyph_rom[77]=12'h088;
        glyph_rom[78]=12'h3FC; glyph_rom[79]=12'h040;
        glyph_rom[80]=12'h3FC; glyph_rom[81]=12'h040;
        glyph_rom[82]=12'h7FE;

        // 忧 U+5FE7
        glyph_rom[84]=12'h200; glyph_rom[85]=12'h214;
        glyph_rom[86]=12'h214; glyph_rom[87]=12'h6D2;
        glyph_rom[88]=12'h63C; glyph_rom[89]=12'h628;
        glyph_rom[90]=12'h228; glyph_rom[91]=12'h228;
        glyph_rom[92]=12'h228; glyph_rom[93]=12'h24A;
        glyph_rom[94]=12'h28E;

        // 郁 U+90C1
        glyph_rom[96]=12'h100; glyph_rom[97]=12'h11E;
        glyph_rom[98]=12'h7D2; glyph_rom[99]=12'h214;
        glyph_rom[100]=12'h7D4; glyph_rom[101]=12'hE54;
        glyph_rom[102]=12'h3D2; glyph_rom[103]=12'h3D2;
        glyph_rom[104]=12'h252; glyph_rom[105]=12'h254;
        glyph_rom[106]=12'h2D0;
    end

    // Scroll state: banner_x = H_ACT - scroll_pos walks from +640 (off right)
    // down to -143 (off left), then wraps. Signed math keeps the partially
    // off-screen frames correct.
    reg [10:0] scroll_pos;   // 0..SPAN-1
    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    wire frame_start = vs_q && !vsync;

    wire signed [10:0] banner_x = $signed({1'b0, H_ACT_R}) -
                                 $signed({1'b0, scroll_pos});
    wire signed [10:0] diff = $signed({1'b0, pixel_x}) - banner_x;
    wire y_band = de && (line_y >= SUB_Y_R) && (line_y < SUB_Y_R + GLYPH_H_R);
    wire in_text = y_band && (diff >= 0) && (diff < TEXT_W_R);
    wire [3:0] glyph_index = diff[7:4];
    wire [3:0] glyph_col = diff[3:0];
    wire [3:0] glyph_row = line_y[3:0] - SUB_Y_ROW;
    wire [7:0] glyph_address = (glyph_index << 3) + (glyph_index << 2) +
                               glyph_row;

    reg [23:0] rgb_q;
    reg [11:0] glyph_row_q;
    reg [3:0] glyph_col_q;
    reg text_bounds_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync_out <= 1'b1;
            vsync_out <= 1'b1;
            de_out <= 1'b0;
            pixel_x_out <= 10'd0;
            rgb_q <= 24'd0;
            glyph_row_q <= 12'd0;
            glyph_col_q <= 4'd0;
            text_bounds_q <= 1'b0;
            scroll_pos <= 11'd0;
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
        end else begin
            hsync_out <= hsync;
            vsync_out <= vsync;
            de_out <= de;
            pixel_x_out <= pixel_x;
            rgb_q <= rgb_in;
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;
            if (frame_start) begin
                if (scroll_pos >= SPAN_R - STEP_R)
                    scroll_pos <= 11'd0;
                else
                    scroll_pos <= scroll_pos + STEP_R;
            end
            text_bounds_q <= in_text && (glyph_col < GLYPH_W);
            if (in_text && (glyph_col < GLYPH_W))
                glyph_row_q <= glyph_rom[glyph_address];
            else
                glyph_row_q <= 12'd0;
            glyph_col_q <= glyph_col;
        end
    end

    wire subtitle_hit = text_bounds_q && glyph_row_q[11 - glyph_col_q];
    assign rgb_out = subtitle_hit ? TEXT_COLOR : rgb_q;
    assign subtitle_active = subtitle_hit;
endmodule
