`timescale 1ns/1ps
module terminal_overlay(
    input wire clk,rst_n,hs,vs,de,
    input wire [9:0] x,y,
    input wire [23:0] rgb,
    input wire [2:0] page,
    input wire emergency,acknowledged,auto_enabled,image_ready,
    input wire content_override,
    input wire [3:0] failure_reason,
    input wire [5:0] available_mask,
    input wire [15:0] event_id,
    input wire [2:0] brightness,contrast,volume_level,
    input wire [4:0] reveal_step,
    output reg hs_out,vs_out,de_out,
    output reg [9:0] x_out,
    output wire [23:0] rgb_out
);
    reg vs_prev;
    reg [10:0] scroll;
    wire [10:0] ticker_x={1'b0,x}+scroll;
    reg [4:0] message;
    reg [5:0] character;
    reg [3:0] row,column;
    reg text_on;
    wire [2:0] ready_count={2'd0,available_mask[0]}+{2'd0,available_mask[1]}+
        {2'd0,available_mask[2]}+{2'd0,available_mask[3]}+
        {2'd0,available_mask[4]}+{2'd0,available_mask[5]};
    always @* begin
        message=0; character=0; row=0; column=0; text_on=0;
        if(y>=8 && y<24) begin
            row=y-8; column=x[3:0];
            if(x>=16 && x<144) begin message=6+page; character=(x-16)>>4; text_on=1; end
            else if(x>=176 && x<336) begin
                message=emergency ? (acknowledged ? 15:14) : (auto_enabled ? 12:13);
                character=(x-176)>>4; text_on=1;
            end
            else if(x>=344 && x<376) begin message=19; character=(x-344)>>4; column=x-344; text_on=1; end
            else if(x>=416 && x<464) begin message=20; character=(x-416)>>4; text_on=1; end
            else if(x>=488 && x<520) begin message=21; character=(x-488)>>4; column=x-488; text_on=1; end
            else if(x>=560) begin
                message=28; text_on=1;
                if(x<592) character=(x-560)>>4;
                else if(x<608) character=2+ready_count;
                else character=x<624 ? 9:10;
            end
        end else if(y>=24 && y<40) begin
            row=y-24; column=x[3:0];
        end else if(y>=440 && y<472) begin
            message=page; character=ticker_x[10:5]; column=ticker_x[4:1]; row=(y-440)>>1; text_on=1;
        end else if(!content_override && !image_ready && y>=166 && y<198 && x>=64 && x<576) begin
            message=6+page; character=(x-64)>>5; column=(x-64)>>1; row=(y-166)>>1; text_on=1;
        end else if(!content_override && !image_ready && y>=230 && y<246) begin
            message=page; character=x[9:4]; column=x[3:0]; row=y-230; text_on=1;
        end else if(!content_override && !image_ready && y>=276 && y<292 && x>=192 && x<448) begin
            case(failure_reason)
                1: message=22;
                2: message=23;
                3: message=24;
                4: message=25;
                5: message=26;
                default: message=16;
            endcase
            character=(x-192)>>4; column=(x-192); row=y-276; text_on=1;
        end else if(!content_override && !image_ready && failure_reason!=0 && y>=308 && y<324 && x>=96 && x<544) begin
            message=27; character=(x-96)>>4; column=x-96; row=y-308; text_on=1;
        end
    end
    wire [15:0] dots;
    terminal_text_rom u_font(.clk(clk),.message(message),.character(character),.row(row),.dots(dots));
    function [7:0] adjust;
        input [7:0] c;
        input [2:0] b,k;
        reg signed [12:0] value,centered;
        begin
            centered=$signed({1'b0,c})-13'sd128;
            case(k)
                1:value=centered-(centered>>>3)+128;
                2:value=centered-(centered>>>2)+128;
                3:value=(centered>>>1)+128;
                4:value=(centered>>>2)+128;
                default:value=centered+128;
            endcase
            if(value<0) value=0; else if(value>255) value=255;
            case(b)
                1:value=value-(value>>>3);
                2:value=value-(value>>>2);
                3:value=value-(value>>>1);
                4:value=value>>>2;
                default:;
            endcase
            adjust=value[7:0];
        end
    endfunction
    function [6:0] seven;
        input [3:0] n;
        begin case(n)
            0:seven=7'b1111110;1:seven=7'b0110000;2:seven=7'b1101101;3:seven=7'b1111001;
            4:seven=7'b0110011;5:seven=7'b1011011;6:seven=7'b1011111;7:seven=7'b1110000;
            8:seven=7'b1111111;9:seven=7'b1111011;10:seven=7'b1110111;11:seven=7'b0011111;
            12:seven=7'b1001110;13:seven=7'b0111101;14:seven=7'b1001111;default:seven=7'b1000111;
        endcase end
    endfunction
    reg [23:0] base;
    reg [3:0] column_q;
    reg text_q,bar_q;
    // Labels occupy the first row; five-segment bars occupy a separate row so
    // the Chinese glyphs cannot be overwritten by the bar color.
    wire label_on = y>=8 && y<24 &&
        ((x>=344 && x<376) || (x>=416 && x<464) || (x>=488 && x<520));
    wire bars = y>=27 && y<35 && (
        (x>=344 && x<356 && brightness<=3'd4) ||
        (x>=358 && x<370 && brightness<=3'd3) ||
        (x>=372 && x<384 && brightness<=3'd2) ||
        (x>=386 && x<398 && brightness<=3'd1) ||
        (x>=400 && x<412 && brightness==3'd0) ||
        (x>=416 && x<428 && contrast<=3'd4) ||
        (x>=430 && x<442 && contrast<=3'd3) ||
        (x>=444 && x<456 && contrast<=3'd2) ||
        (x>=458 && x<470 && contrast<=3'd1) ||
        (x>=472 && x<484 && contrast==3'd0) ||
        (x>=488 && x<500 && volume_level<=3'd4) ||
        (x>=502 && x<514 && volume_level<=3'd3) ||
        (x>=516 && x<528 && volume_level<=3'd2) ||
        (x>=530 && x<542 && volume_level<=3'd1) ||
        (x>=544 && x<556 && volume_level==3'd0));
    wire [9:0] boundary={reveal_step,5'b0};
    wire [23:0] adjusted={adjust(rgb[23:16],brightness,contrast),adjust(rgb[15:8],brightness,contrast),adjust(rgb[7:0],brightness,contrast)};
    wire [23:0] fallback=emergency ? 24'h681b29:24'h123f68;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin hs_out<=1;vs_out<=1;de_out<=0;x_out<=0;base<=0;column_q<=0;text_q<=0;bar_q<=0;vs_prev<=1;scroll<=0; end
        else begin
            vs_prev<=vs;
            if(vs_prev && !vs) scroll<=scroll+4;
            hs_out<=hs;vs_out<=vs;de_out<=de;x_out<=x;
            column_q<=column; text_q<=text_on || label_on; bar_q<=bars;
            if(y<40 || y>=436) base<=24'h0b182a;
            else if(!image_ready) base<=fallback;
            else if(!emergency && reveal_step<20 && x>=boundary) base<=24'h0b182a;
            else base<=adjusted;
        end
    end
    assign rgb_out = !de_out ? 24'd0 :
        text_q && dots[15-column_q] ? 24'hffffff :
        bar_q ? 24'h5de3a4 : base;
endmodule
