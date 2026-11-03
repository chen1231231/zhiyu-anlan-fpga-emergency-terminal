`timescale 1ns/1ps

// Starts the storage pipeline at power-up and retries after media or runtime
// failures. Frame-valid state lives outside this controller, so a rescan keeps
// the last verified SDRAM pages visible while the card is reinitialized.
module terminal_media_recovery #(
    parameter integer RETRY_TICKS = 5
)(
    input wire clk,
    input wire rst_n,
    input wire memory_ready,
    input wire ingest_busy,
    input wire ingest_done,
    input wire [7:0] ingest_error,
    input wire runtime_fault,
    input wire retry_tick,
    output reg ingest_start,
    output reg recovery_active,
    output reg media_healthy
);
    localparam ST_BOOT=2'd0,ST_RUN=2'd1,ST_WAIT=2'd2;
    reg [1:0] state;
    reg [2:0] retry_count;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_BOOT; retry_count<=0; ingest_start<=0;
            recovery_active<=1; media_healthy<=0;
        end else begin
            ingest_start<=0;
            case(state)
                ST_BOOT: if(memory_ready && !ingest_busy) begin
                    ingest_start<=1; state<=ST_RUN; recovery_active<=1;
                end
                ST_RUN: begin
                    if(ingest_done) begin
                        if(ingest_error==0) begin
                            media_healthy<=1; recovery_active<=0;
                        end else begin
                            media_healthy<=0; recovery_active<=1;
                            retry_count<=0; state<=ST_WAIT;
                        end
                    end else if(media_healthy && runtime_fault) begin
                        media_healthy<=0; recovery_active<=1;
                        retry_count<=0; state<=ST_WAIT;
                    end
                end
                ST_WAIT: begin
                    if(retry_tick) begin
                        if(retry_count>=RETRY_TICKS-1) begin
                            retry_count<=0;
                            if(memory_ready && !ingest_busy) begin
                                ingest_start<=1; state<=ST_RUN;
                            end
                        end else retry_count<=retry_count+1'b1;
                    end
                end
                default: state<=ST_BOOT;
            endcase
        end
    end
endmodule
