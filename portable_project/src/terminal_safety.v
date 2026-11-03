`timescale 1ns/1ps
// Only the four board switches emulate sensors. No physical sensor is claimed.
module terminal_safety #(
    parameter integer CLOCK_HZ=25000000,
    parameter integer DEBOUNCE_CYCLES=500000
)(
    input wire clk,rst_n,
    input wire [3:0] sw,
    input wire emergency,acknowledged,
    input wire [15:0] event_id,
    input wire [1:0] scene_mode,event_type,
    input wire next_press,page_hold,frame_start,auto_enabled,
    input wire pending_confirm,operator_confirm,
    input wire plan_valid,
    input wire [3:0] plan_emergency_seconds,
    output reg sensor_trigger,
    output reg [3:0] stable_sw,
    output reg [1:0] zone,
    output reg extra_block,
    output wire [1:0] exits_open,
    output wire [3:0] hazard_mask,
    output reg [1:0] view,
    output reg [9:0] elapsed,
    output reg [67:0] history,
    output reg [7:0] history_scene,
    output reg [2:0] history_count,
    output wire [1:0] alert_level,
    output reg route_pending,
    output wire [1:0] recommended_exit,
    output wire [6:0] route_score,
    output reg drill_report,
    output reg [6:0] drill_score,
    output reg [7:0] drill_confirm_seconds,
    output reg [9:0] drill_ack_seconds,
    output reg [9:0] drill_total_seconds,
    output reg [3:0] drill_route_changes,
    output reg drill_corrected,
    output reg second_toggle,
    output wire startup
);
    reg [3:0] sw_meta,sw_sync,candidate;
    reg [19:0] debounce;
    reg settled,armed;
    reg [24:0] second_count;
    reg [1:0] startup_seconds;
    reg [9:0] carousel_frames;
    reg emergency_q,ack_q;
    reg [15:0] id_q;
    reg pending_q;
    reg [24:0] confirm_count;
    reg [7:0] confirm_seconds;
    reg [3:0] route_changes;
    reg corrected;
    wire [9:0] carousel_limit=plan_valid ?
        (({6'd0,plan_emergency_seconds}<<6)-({6'd0,plan_emergency_seconds}<<2)-1'b1) : 10'd119;
    // Group encoding when SW3 is high: 01 west, 10 east, 00/11 all.
    assign hazard_mask = !extra_block ? (4'b0001 << zone) :
                         zone==1 ? 4'b0101 : zone==2 ? 4'b1010 : 4'b1111;
    // A/C close exit one; B/D close exit two. Derive both from the same mask.
    assign exits_open = {!(hazard_mask[1] || hazard_mask[3]),
                         !(hazard_mask[0] || hazard_mask[2])};
    assign recommended_exit = exits_open[0] ? 2'd1 : exits_open[1] ? 2'd2 : 2'd0;
    assign route_score = exits_open==0 ? 7'd0 : extra_block ? 7'd70 : 7'd95;
    // 0 blue/normal, 1 yellow/pre-alert, 2 orange/local evacuation,
    // 3 red/half-zone or all-zone. Level follows the accepted route snapshot,
    // including a reduction back to a single zone; elapsed time cannot latch red.
    assign alert_level = pending_confirm ? 2'd1 : !emergency ? 2'd0 :
                         (extra_block || exits_open==0) ? 2'd3 : 2'd2;
    assign startup = startup_seconds<2;

    function [6:0] score_drill;
        input [7:0] confirm_s;
        input [9:0] ack_s,total_s;
        input acked,route_wait,was_corrected;
        input [3:0] changes;
        reg [7:0] penalty;
        begin
            penalty=0;
            if(confirm_s>10) penalty=penalty+20; else if(confirm_s>5) penalty=penalty+10;
            if(!acked) penalty=penalty+25; else if(ack_s>15) penalty=penalty+15;
            if(total_s>180) penalty=penalty+10;
            if(route_wait) penalty=penalty+20;
            if(changes>1) penalty=penalty+10;
            if(was_corrected) penalty=penalty+10;
            score_drill=penalty>=100 ? 0 : 100-penalty;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sw_meta<=0;sw_sync<=0;candidate<=0;stable_sw<=0;
            debounce<=0;settled<=0;armed<=0;sensor_trigger<=0;
            second_count<=0;startup_seconds<=0;emergency_q<=0;ack_q<=0;id_q<=0;carousel_frames<=0;
            pending_q<=0;confirm_count<=0;confirm_seconds<=0;route_changes<=0;corrected<=0;
            zone<=0;extra_block<=0;view<=0;elapsed<=0;history<=0;history_scene<=0;history_count<=0;
            route_pending<=0;drill_report<=0;drill_score<=0;drill_confirm_seconds<=0;
            drill_ack_seconds<=0;drill_total_seconds<=0;drill_route_changes<=0;drill_corrected<=0;
            second_toggle<=0;
        end else begin
            sw_meta<=sw;sw_sync<=sw_meta;sensor_trigger<=0;
            if(sw_sync!=candidate) begin candidate<=sw_sync;debounce<=0;end
            else if(debounce<DEBOUNCE_CYCLES-1) debounce<=debounce+1'b1;
            else if(!settled || stable_sw!=candidate) begin
                stable_sw<=candidate;settled<=1;
                // Require a confirmed low after reset, then a debounced rising edge.
                if(!candidate[3]) armed<=1;
                else if(settled && armed) begin sensor_trigger<=1;armed<=0;end
            end
            emergency_q<=emergency;ack_q<=acknowledged;id_q<=event_id;pending_q<=pending_confirm;
            if(pending_confirm && !emergency) begin
                if(confirm_count==CLOCK_HZ-1) begin
                    confirm_count<=0;
                    if(confirm_seconds<255) confirm_seconds<=confirm_seconds+1'b1;
                end else confirm_count<=confirm_count+1'b1;
            end else confirm_count<=0;
            if(pending_q && !pending_confirm && !emergency && scene_mode==1) corrected<=1;
            if(second_count==CLOCK_HZ-1) begin
                second_count<=0;
                second_toggle<=~second_toggle;
                if(startup_seconds<2) startup_seconds<=startup_seconds+1'b1;
                if(emergency && elapsed<999) elapsed<=elapsed+1'b1;
            end else second_count<=second_count+1'b1;
            if(!emergency) begin
                zone<=stable_sw[1:0];extra_block<=stable_sw[2];view<=0;route_pending<=0;
                if(drill_report && next_press) drill_report<=0;
                if(drill_report && scene_mode!=1) drill_report<=0;
            end else begin
                if(next_press) view<=view==0 ? 1:0;
                if(page_hold) view<=view==2 ? 3 : view==3 ? 0:2;
                if(frame_start && auto_enabled && view<2) begin
                    if(carousel_frames==carousel_limit) begin
                        carousel_frames<=0; view<=view==0 ? 1:0;
                    end else carousel_frames<=carousel_frames+1'b1;
                end else if(!auto_enabled || view>=2) carousel_frames<=0;
                // Drill mode accepts changing simulated hazards immediately.
                // Real campus/mall alerts hold the published route until KEY3.
                if(stable_sw[2:0]!={extra_block,zone}) begin
                    if(scene_mode==1) begin
                        zone<=stable_sw[1:0];extra_block<=stable_sw[2];route_pending<=0;
                        if(route_changes<15) route_changes<=route_changes+1'b1;
                    end else route_pending<=1;
                end else route_pending<=0;
                if(route_pending && operator_confirm) begin
                    zone<=stable_sw[1:0];extra_block<=stable_sw[2];route_pending<=0;
                    if(route_changes<15) route_changes<=route_changes+1'b1;
                end
            end
            if(emergency && (!emergency_q || event_id!=id_q)) begin
                zone<=stable_sw[1:0];extra_block<=stable_sw[2];view<=1;
                elapsed<=0;second_count<=0;carousel_frames<=0;
                route_pending<=0;route_changes<=0;drill_report<=0;
                drill_ack_seconds<=0;
                // 17 bits/record: type[16:15],group[14],zone[13:12],state[11:10],seconds[9:0].
                history_scene<={history_scene[5:0],scene_mode};
                if(emergency_q)
                    history<={history[50:17],history[16:12],2'b11,history[9:0],
                        event_type,stable_sw[2],stable_sw[1:0],2'b00,10'd0};
                else history<={history[50:0],event_type,stable_sw[2],stable_sw[1:0],2'b00,10'd0};
                if(history_count<4) history_count<=history_count+1'b1;
            end else if(emergency_q) begin
                history[9:0]<=elapsed;
                history[14:12]<={extra_block,zone};
                if(!emergency) history[11:10]<=2'b10;
                else if(acknowledged && !ack_q) history[11:10]<=2'b01;
            end
            if(acknowledged && !ack_q && scene_mode==1) drill_ack_seconds<=elapsed;
            if(emergency_q && !emergency && scene_mode==1) begin
                drill_report<=1;
                drill_confirm_seconds<=confirm_seconds;
                drill_total_seconds<=elapsed;
                drill_route_changes<=route_changes;
                drill_corrected<=corrected;
                drill_score<=score_drill(confirm_seconds,drill_ack_seconds,elapsed,
                                         ack_q,route_pending,corrected,route_changes);
                confirm_seconds<=0;corrected<=0;
            end else if(!pending_confirm && !emergency && !drill_report && scene_mode!=1) begin
                confirm_seconds<=0;corrected<=0;
            end
        end
    end
endmodule
