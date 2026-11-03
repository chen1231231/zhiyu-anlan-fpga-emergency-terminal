`timescale 1ns/1ps
// Requests are one-cycle pulses. Capture BOTH when image/audio issue together,
// retain ownership through sector_done, and alternate when both are waiting.
module media_sector_arbiter (
    input wire clk, rst_n,
    input wire image_req, input wire [31:0] image_lba,
    output wire image_busy, image_valid, image_done,
    input wire audio_req, input wire [31:0] audio_lba,
    output wire audio_busy, audio_valid, audio_done,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire sector_busy, sector_valid, sector_done
);
    reg image_pending, audio_pending;
    reg [31:0] image_lba_q, audio_lba_q;
    reg [1:0] owner;
    reg last_audio;
    assign image_busy = image_pending || owner != 0 || sector_busy;
    assign audio_busy = audio_pending || owner != 0 || sector_busy;
    assign image_valid = owner == 1 && sector_valid;
    assign image_done = owner == 1 && sector_done;
    assign audio_valid = owner == 2 && sector_valid;
    assign audio_done = owner == 2 && sector_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            image_pending<=0; audio_pending<=0; owner<=0; last_audio<=0;
            image_lba_q<=0; audio_lba_q<=0; sector_req<=0; sector_lba<=0;
        end else begin
            sector_req<=0;
            if(image_req) begin image_pending<=1; image_lba_q<=image_lba; end
            if(audio_req) begin audio_pending<=1; audio_lba_q<=audio_lba; end
            if(owner != 0) begin
                if(sector_done) owner<=0;
            end else if(!sector_busy && !sector_req) begin
                if(audio_pending && (!image_pending || !last_audio)) begin
                    audio_pending<=0; owner<=2; last_audio<=1;
                    sector_lba<=audio_lba_q; sector_req<=1;
                end else if(image_pending) begin
                    image_pending<=0; owner<=1; last_audio<=0;
                    sector_lba<=image_lba_q; sector_req<=1;
                end
            end
        end
    end
endmodule
