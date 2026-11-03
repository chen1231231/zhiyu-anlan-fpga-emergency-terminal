`timescale 1ns/1ps

module tb_tf_pcm_audio_player;
    reg mem_clk=0, pix_clk=0, mem_rst_n=0, pix_rst_n=0;
    always #5 mem_clk=~mem_clk;
    always #7 pix_clk=~pix_clk;

    reg alarm_enable=0, audio_test=0;
    reg [1:0] scene_mode=0, selected_type=0;
    reg plan_valid=0;
    reg [7:0] audio_map=8'h39;
    wire [1:0] event_type;
    terminal_plan_audio_select selection(.scene_mode(scene_mode),.event_type(selected_type),
        .plan_valid(plan_valid),.audio_map(audio_map),.player_event_type(event_type));
    reg [7:0] volume=8'd128;
    reg [3:0] audio_available=0;
    wire file_start, file_stop, sector_admit;
    wire [1:0] file_select;
    reg file_busy=0, file_done=0, file_valid=0;
    reg [7:0] file_byte=0, file_error=0;
    wire sample_valid;
    wire signed [15:0] sample_left, sample_right;
    wire underflow;
    wire pcm_starved;
    wire [7:0] player_error;

    tf_pcm_audio_player #(.PIXEL_CLOCK_HZ(480000),.OUTPUT_SAMPLE_HZ(48000)) dut(.*);

    integer starts=0, sent=0, remaining=0;
    reg inject_error=0;
    always @(posedge mem_clk) begin
        file_done<=0;
        file_valid<=0;
        if(file_stop) begin
            file_busy<=0;
            remaining<=0;
        end else if(file_start) begin
            starts<=starts+1;
            sent<=0;
            remaining<=259;
            file_busy<=1;
            file_error<=0;
        end else if(file_busy) begin
            if(remaining!=0) begin
                file_valid<=1;
                if(sent==0) file_byte<=8'h01;
                else if(sent==1) file_byte<=8'hFE;
                else if(sent==2) file_byte<=8'h7F;
                else if(sent==3) file_byte<=8'h80;
                else if(sent==256) file_byte<=8'h11;
                else if(sent==257) file_byte<=8'h22;
                else if(sent==258) file_byte<=8'h33;
                else file_byte<=0;
                sent<=sent+1;
                remaining<=remaining-1;
            end else begin
                file_busy<=0;
                file_done<=1;
                file_error<=inject_error ? 8'h55 : 0;
            end
        end
    end

    integer checked=0, before_error_starts, scene, hazard;
    reg signed [15:0] expected [0:11];
    initial begin
        // With the release plan enabled, a mall crowd/power/escalator alert
        // must never play the campus quake/flood recordings.
        plan_valid=1;
        for(scene=0;scene<3;scene=scene+1) begin
            scene_mode=scene;
            for(hazard=0;hazard<4;hazard=hazard+1) begin
                selected_type=hazard; #1;
                if(scene==2 && hazard!=0) begin
                    if(event_type!=3)$fatal(1,"mall hazard selected campus voice");
                end else if(event_type!=hazard)$fatal(1,"default plan hazard voice mismatch");
            end
        end
        // Custom campus mapping: all events use the generic alarm.
        scene_mode=0; audio_map=0;
        for(hazard=0;hazard<4;hazard=hazard+1) begin
            selected_type=hazard; #1;
            if(event_type!=3)$fatal(1,"custom plan audio map ignored");
        end
        scene_mode=2; audio_map=8'hff; selected_type=1; #1;
        if(event_type!=3)$fatal(1,"custom plan bypassed mall voice guard");
        scene_mode=0;selected_type=0;plan_valid=0;audio_map=8'h39;
        expected[0]=128; expected[1]=128; expected[2]=128;
        expected[3]=-256; expected[4]=-256; expected[5]=-256;
        expected[6]=16256; expected[7]=16256; expected[8]=16256;
        expected[9]=-16384; expected[10]=-16384; expected[11]=-16384;

        repeat(5) @(negedge mem_clk); mem_rst_n=1; pix_rst_n=1;
        alarm_enable=1;
        repeat(20) @(negedge mem_clk);
        if(starts!=0) $fatal(1,"started without an available file");
        audio_available=4'b1111;
        wait(starts==1);
        if(file_select!=1) $fatal(1,"fire mapped to file %0d",file_select);

        wait(sample_valid && sample_left==128);
        while(checked<12) begin
            @(negedge pix_clk);
            if(sample_valid) begin
                if(pcm_starved) $fatal(1,"valid PCM incorrectly reported as starved");
                if(sample_left!==expected[checked])
                    $fatal(1,"sample %0d got %0d expected %0d",checked,sample_left,expected[checked]);
                if(sample_right!==sample_left) $fatal(1,"stereo mismatch");
                checked=checked+1;
            end
        end
        wait(starts==2);
        if(dut.u_audio_fifo.mem[64]!==32'h00332211)
            $fatal(1,"partial tail was not zero padded: %08x",dut.u_audio_fifo.mem[64]);

        selected_type=1;
        wait(file_select==2 && starts>=3);
        audio_test=1;
        wait(file_select==0 && starts>=4);

        inject_error=1;
        wait(file_done && file_error==8'h55);
        repeat(10) @(negedge mem_clk);
        before_error_starts=starts;
        repeat(100) @(negedge mem_clk);
        if(starts!=before_error_starts) $fatal(1,"errored file restarted");
        if(player_error!=8'h55) $fatal(1,"player error not latched: %02x",player_error);

        alarm_enable=0; audio_test=0;
        repeat(20) @(negedge mem_clk);
        if(!sector_admit && file_busy) $fatal(1,"inconsistent stop state");
        $display("PASS PCM event selection, plan mappings and mall voice guard, 3x samples, loop, switch, tail and error stop");
        $finish;
    end

    initial begin #2000000; $fatal(1,"simulation timeout"); end
endmodule

// Small behavioral model for the generated asynchronous FIFO used by the player.
module rfifo_32_32_512 #(
    parameter DATA_WIDTH_W=32, DATA_WIDTH_R=32, ADDR_WIDTH_W=9, ADDR_WIDTH_R=9,
    parameter AL_FULL_NUM=380, AL_EMPTY_NUM=64, SHOW_AHEAD_EN=1, OUTREG_EN="NOREG"
)(
    input rst,clkw,clkr,we,re,
    input [DATA_WIDTH_W-1:0] di,
    output [DATA_WIDTH_R-1:0] dout,
    output valid,full_flag,empty_flag,afull,aempty,
    output [ADDR_WIDTH_W-1:0] wrusedw,
    output [ADDR_WIDTH_R-1:0] rdusedw
);
    reg [31:0] mem[0:511];
    integer wp=0,rp=0;
    always @(posedge clkw or posedge rst) begin
        if(rst) wp<=0;
        else if(we && !full_flag) begin mem[wp&511]<=di; wp<=wp+1; end
    end
    always @(posedge clkr or posedge rst) begin
        if(rst) rp<=0;
        else if(re && !empty_flag) rp<=rp+1;
    end
    wire [9:0] used=wp-rp;
    assign dout=mem[rp&511];
    assign valid=!empty_flag;
    assign empty_flag=(used==0);
    assign full_flag=(used>=511);
    assign afull=(used>=AL_FULL_NUM);
    assign aempty=(used<=AL_EMPTY_NUM);
    assign wrusedw=used[8:0];
    assign rdusedw=used[8:0];
endmodule
