`timescale 1ns/1ps
// TF-free alternating 800/1200 Hz, pulsed alarm. Preserve the player's 48k tick.
// A file error/missing catalog or >250ms FIFO starvation enables fallback.
module terminal_alarm_fallback #(
    parameter integer SAMPLE_HZ=48000
)(
    input wire clk,rst_n,sample_valid,alarm_enable,pcm_fault,underflow,
    input wire [2:0] volume_level,
    input wire signed [15:0] pcm,
    output wire signed [15:0] sample_out,
    output wire fallback_active
);
    reg [13:0] bad_samples;
    reg [15:0] cadence;
    reg [5:0] half_period;
    reg polarity;
    wire [5:0] limit=cadence<SAMPLE_HZ/4 ? 6'd29:6'd19;
    wire signed [15:0] amplitude = volume_level==0 ? 16'sd12000 :
        volume_level==1 ? 16'sd9000 : volume_level==2 ? 16'sd6000 :
        volume_level==3 ? 16'sd3000:16'sd0;
    assign fallback_active=alarm_enable && (pcm_fault || bad_samples>=SAMPLE_HZ/4);
    assign sample_out=fallback_active ?
        (cadence>=SAMPLE_HZ*3/4 ? 16'sd0 : polarity ? amplitude:-amplitude) : pcm;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin bad_samples<=0;cadence<=0;half_period<=0;polarity<=0;end
        else if(!alarm_enable) begin bad_samples<=0;cadence<=0;half_period<=0;polarity<=0;end
        else if(sample_valid) begin
            if(!underflow) bad_samples<=0;
            else if(bad_samples<SAMPLE_HZ/4) bad_samples<=bad_samples+1'b1;
            if(cadence==SAMPLE_HZ-1) cadence<=0;else cadence<=cadence+1'b1;
            if(half_period>=limit) begin half_period<=0;polarity<=~polarity;end
            else half_period<=half_period+1'b1;
        end
    end
endmodule
