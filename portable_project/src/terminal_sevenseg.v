`timescale 1ns/1ps

// Six-digit common-anode display used by the EG4S20 board example.
// Digits show: mode, selected/event code, volume level, brightness level,
// contrast level, and the setting currently selected by KEY4 long press.
module terminal_sevenseg #(parameter integer CLOCK_HZ=50000000)(
    input wire clk, input wire rst_n,
    input wire emergency,
    input wire [1:0] event_type, selected_type,
    input wire [2:0] volume_level,
    input wire [2:0] brightness, contrast,
    input wire [1:0] adjust_menu,
    output reg [5:0] seg_sel, output reg [7:0] seg_data
);
    localparam integer SCAN_CYCLES=CLOCK_HZ/1200;
    reg [$clog2(SCAN_CYCLES)-1:0] scan_count;
    reg [2:0] scan_digit;
    wire [1:0] shown_type = emergency ? event_type : selected_type;
    wire [3:0] nibble =
        scan_digit == 0 ? (emergency ? 4'he : 4'hd) :
        scan_digit == 1 ? ({2'b0,shown_type} + 4'd1) :
        scan_digit == 2 ? (volume_level + 4'd1) :
        scan_digit == 3 ? (brightness + 4'd1) :
        scan_digit == 4 ? (contrast + 4'd1) : (adjust_menu + 4'd1);
    function [7:0] decode;
        input [3:0] n;
        begin case(n)
            4'h0: decode=8'b1100_0000; 4'h1: decode=8'b1111_1001;
            4'h2: decode=8'b1010_0100; 4'h3: decode=8'b1011_0000;
            4'h4: decode=8'b1001_1001; 4'h5: decode=8'b1001_0010;
            4'h6: decode=8'b1000_0010; 4'h7: decode=8'b1111_1000;
            4'h8: decode=8'b1000_0000; 4'h9: decode=8'b1001_0000;
            4'ha: decode=8'b1000_1000; 4'hb: decode=8'b1000_0011;
            4'hc: decode=8'b1100_0110; 4'hd: decode=8'b1010_0001;
            4'he: decode=8'b1000_0110; default: decode=8'b1000_1110;
        endcase end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_count<=0; scan_digit<=0; seg_sel<=6'b111111; seg_data<=8'hff;
        end else begin
            if (scan_count==SCAN_CYCLES-1) begin
                scan_count<=0; scan_digit <= scan_digit==5 ? 0 : scan_digit+1'b1;
            end else scan_count<=scan_count+1'b1;
            case(scan_digit)
                0: seg_sel<=6'b11_1110; 1: seg_sel<=6'b11_1101;
                2: seg_sel<=6'b11_1011; 3: seg_sel<=6'b11_0111;
                4: seg_sel<=6'b10_1111; default: seg_sel<=6'b01_1111;
            endcase
            seg_data<=decode(nibble);
        end
    end
endmodule
