`timescale 1ns/1ps

// The vendor application port accepts continuous bursts, not independent
// ready/valid beats. Grant ownership before launch and never truncate a burst.
module media_sdram_arbiter #(
    parameter integer TURNAROUND_CYCLES = 12
) (
    input wire clk,
    input wire rst_n,
    input wire controller_busy,
    input wire refresh_active,
    input wire read_request,
    input wire read_busy,
    input wire write_request,
    input wire write_busy,
    output wire read_grant,
    output wire write_grant,
    output wire idle
);
    localparam IDLE = 2'd0, READ = 2'd1, WRITE = 2'd2, DRAIN = 2'd3;
    reg [1:0] owner;
    localparam integer GAP_W = $clog2(TURNAROUND_CYCLES + 1);
    reg [GAP_W-1:0] quiet_count;
    assign idle = owner == IDLE;
    assign read_grant = idle && !controller_busy && !refresh_active &&
                        read_request;
    assign write_grant = idle && !controller_busy && !refresh_active &&
                         !read_request && write_request;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner <= IDLE;
            quiet_count <= 0;
        end else begin
            case (owner)
                IDLE: begin
                    if (read_grant) owner <= READ;
                    else if (write_grant) owner <= WRITE;
                end
                READ: if (!read_busy && !controller_busy) owner <= IDLE;
                WRITE: if (!write_busy) begin
                    quiet_count <= TURNAROUND_CYCLES;
                    owner <= DRAIN;
                end
                DRAIN: begin
                    if (quiet_count != 0) quiet_count <= quiet_count - 1'b1;
                    else if (!controller_busy) owner <= IDLE;
                end
                default: owner <= IDLE;
            endcase
        end
    end
endmodule
