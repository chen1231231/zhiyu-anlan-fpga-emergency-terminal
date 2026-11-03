`timescale 1ns/1ps
// Combinational geometry + one-cycle font pipeline; no frame-buffer allocation.
module terminal_safety_overlay(
    input wire clk,rst_n,frame_start,enabled,
    input wire [9:0] x,y,
    input wire [1:0] view,zone,exits_open,
    input wire [3:0] hazard_mask,
    input wire audio_active,pcm_valid,
    input wire signed [15:0] pcm_sample,
    input wire [9:0] elapsed,
    input wire [67:0] history,
    input wire [7:0] history_scene,
    input wire [2:0] history_count,
    input wire emergency,acknowledged,pending_confirm,clear_pending,auto_enabled,
    input wire [1:0] scene_mode,event_type,
    input wire [1:0] alert_level,recommended_exit,
    input wire route_pending,
    input wire [6:0] route_score,drill_score,
    input wire drill_report,
    input wire [7:0] drill_confirm_seconds,
    input wire [9:0] drill_ack_seconds,drill_total_seconds,
    input wire [3:0] drill_route_changes,
    input wire drill_corrected,
    input wire [5:0] available,
    input wire [3:0] audio_available,
    input wire audio_verified,asset_failed,
    input wire card_ok,memory_ok,clock_ok,fallback_active,
    output reg [23:0] rgb_out,
    output reg draw
);
    localparam BG=24'h0d1c30,WHITE=24'hffffff,GREEN=24'h37efad,RED=24'hff4858;
    reg [5:0] animation;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) animation<=0;else if(frame_start) animation<=animation+1'b1;
    wire blink=animation[4];
    wire content=y>=40 && y<436;
    wire scene_strip=y>=24 && y<40 && x>=16 && x<320;
    wire mall_heading=emergency && scene_mode==2 && y>=8 && y<24 && x>=16 && x<160;
    wire confirmation=pending_confirm || clear_pending;
    wire alert_ticker=emergency && !confirmation && y>=440 && y<472;
    wire confirmation_area=confirmation && y>=40;
    // Cover the entire legacy asset counter, including its rightmost /6 glyph.
    wire level_badge=y>=8 && y<24 && x>=552;
    wire report_footer=drill_report && y>=440 && y<472;
    wire border=emergency && content && (x<4 || x>=636 || y<44 || y>=432);
    wire [1:0] block_zone={y>=240,x>=320};
    wire block_rect=(x>=96 && x<264 || x>=376 && x<544) &&
        (y>=144 && y<216 || y>=288 && y<360);
    wire west_path=exits_open[0] && x>=40 && x<320;
    wire east_path=exits_open[1] && x>=320 && x<600;
    wire corridor=y>=234 && y<254 && (west_path || east_path);
    // Repeated chevrons remain within the chosen, open corridor.
    wire [5:0] phase_w=x[5:0]+animation;
    wire [5:0] phase_e=x[5:0]-animation;
    wire [4:0] dy=y>=244 ? y-244:244-y;
    wire arrow=y>=236 && y<252 &&
        (west_path && phase_w>=dy && phase_w<=dy+3 ||
         east_path && phase_e>=16-dy && phase_e<=19-dy);
    // 32 recent 1ms PCM envelopes, not a synthetic spectrum.
    // Two-pixel strokes with two transparent pixels between neighboring bars.
    reg [127:0] audio_history;
    reg [5:0] audio_count;
    reg [3:0] audio_peak;
    wire [15:0] pcm_abs=pcm_sample[15] ? (~pcm_sample+16'd1):pcm_sample;
    wire [3:0] pcm_level=pcm_abs[15] ? 4'd15:pcm_abs[14:11];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin audio_history<=0;audio_count<=0;audio_peak<=0;end
        else if(!audio_active || acknowledged || !emergency) begin
            audio_history<=0;audio_count<=0;audio_peak<=0;
        end else begin
            if(pcm_valid) begin
                if(audio_count==47) begin
                    audio_history<={audio_history[123:0],pcm_level>audio_peak ? pcm_level:audio_peak};
                    audio_count<=0;audio_peak<=0;
                end else begin
                    audio_count<=audio_count+1'b1;
                    if(pcm_level>audio_peak) audio_peak<=pcm_level;
                end
            end
        end
    end
    wire audio_page=emergency && view==0 && !confirmation && !drill_report;
    wire [9:0] audio_left=10'd64;
    wire [9:0] audio_top=scene_mode==2 ? 10'd64:10'd364;
    wire audio_panel=audio_page && x>=audio_left && x<audio_left+512 &&
                     y>=audio_top && y<audio_top+32;
    wire [9:0] audio_dx=x-audio_left,audio_dy=y-audio_top;
    wire [4:0] audio_index=audio_dx[8:4];
    wire [3:0] audio_level=audio_history[audio_index*4 +: 4];
    // Continuous strokes expand above and below the same centerline.
    wire [3:0] audio_rise=audio_dy<16 ? 15-audio_dy:audio_dy-16;
    wire audio_bar=!audio_dx[1] && audio_level!=0 && audio_rise<=audio_level;
    // Vivid cyan-green center fading continuously to bright yellow tips.
    wire [7:0] audio_red={audio_rise,audio_rise};
    wire [7:0] audio_green={4'hf,~audio_rise};
    wire [7:0] audio_blue={1'b0,~audio_rise,3'b111};
    wire audio_pixel=audio_panel && audio_bar && audio_active && !acknowledged;
    reg [6:0] message;
    reg [5:0] character;
    reg [3:0] row,column;
    reg text_on;
    reg [23:0] base,text_color;
    reg [16:0] record;
    reg [1:0] record_row;
    reg [1:0] record_scene;
    reg [9:0] seconds_value;
    reg [2:0] diagnostic_row;
    reg [3:0] digit;
    reg [2:0] ready_count;
    reg [2:0] image_verified_count;
    reg [2:0] audio_verified_count;
    reg [9:0] mall_primary_start,mall_secondary_start,mall_english_start,mall_action_start;
    always @* begin
        message=0;character=0;row=y[3:0];column=x[3:0];text_on=0;
        base=BG;text_color=WHITE;record=0;record_row=0;record_scene=0;seconds_value=elapsed;diagnostic_row=0;digit=0;
        ready_count={2'd0,available[0]}+{2'd0,available[1]}+{2'd0,available[2]}+
            {2'd0,available[3]}+{2'd0,available[4]}+{2'd0,available[5]};
        image_verified_count=ready_count;
        audio_verified_count=audio_verified ? 3'd4:3'd0;
        case(event_type)
            0:begin mall_primary_start=176;mall_secondary_start=232;mall_english_start=240;mall_action_start=192;end
            1:begin mall_primary_start=144;mall_secondary_start=240;mall_english_start=232;mall_action_start=144;end
            2:begin mall_primary_start=144;mall_secondary_start=248;mall_english_start=216;mall_action_start=96;end
            default:begin mall_primary_start=144;mall_secondary_start=224;mall_english_start=200;mall_action_start=200;end
        endcase
        if(level_badge) begin
            base=alert_level==0 ? 24'h2577c7 : alert_level==1 ? 24'hd9a400 :
                 alert_level==2 ? 24'he96a19 : RED;
            row=y-8;text_on=1;
            if(x<616) begin message=95;character=(x-552)>>4;column=x-552;end
            else if(x<632) begin message=25;character=alert_level;column=x-616;end
            else text_on=0;
            text_color=WHITE;
        end else if(audio_pixel) begin
            base={audio_red,audio_green,audio_blue};
        end else if(scene_strip) begin
            message=scene_mode==2 ? 53:scene_mode==1 ? 54:52;
            character=(x-16)>>4;column=x-16;row=y-24;text_on=x<80;
            if(x>=112 && x<176) begin
                message=scene_mode==2 ? 39+event_type:26+event_type;
                character=(x-112)>>4;column=x-112;text_on=1;
            end
            if(x>=192) begin
                message=auto_enabled ? 69:70;character=(x-192)>>4;column=x-192;text_on=1;
                text_color=auto_enabled ? GREEN:24'hffd166;
            end
        end else if(mall_heading) begin
            message=39+event_type;character=(x-16)>>4;column=x-16;row=y-8;text_on=1;
        end else if(alert_ticker) begin
            base=acknowledged ? 24'h4b2030:24'h681b29;
            text_color=24'hffffff;
            if(y<456) begin
                message=exits_open==0 ? 4:exits_open[0] ? 6:7;
                character=(x-16)>>4;column=x-16;row=y-440;text_on=x>=16;
                text_color=24'hffd166;
            end else if(x>=16 && x<624) begin
                message=exits_open==0 ? 56:exits_open[0] ? 71:72;
                character=(x-16)>>4;column=x-16;row=y-456;text_on=1;
            end
        end else if(report_footer) begin
            base=24'h12304b;text_color=24'hffd166;
            message=y<456 ? 92:93;character=(x-176)>>4;column=x-176;
            row=y<456 ? y-440:y-456;text_on=x>=176 && x<464;
        end else if(pending_confirm || clear_pending) begin
            base = pending_confirm ? 24'h4b3210 : 24'h421526;
            if(y<52 || y>=424 || x<12 || x>=628) base=pending_confirm ? 24'hf2a900:RED;
            // Warning triangle for publication; boxed X for clearing.
            if(pending_confirm && y>=104 && y<200 && x>=272 && x<368 &&
               x>=320-(y-104)/2 && x<=320+(y-104)/2) base=24'hffd166;
            if(pending_confirm && x>=316 && x<324 &&
               (y>=140 && y<172 || y>=180 && y<188)) base=BG;
            if(clear_pending && x>=280 && x<360 && y>=112 && y<192) begin
                if(x<286 || x>=354 || y<118 || y>=186) base=RED;
                if((x+y>=466 && x+y<478) || (x-y>=162 && x-y<174)) base=WHITE;
            end
            if(y>=56 && y<88 && x>=224 && x<416) begin
                message = pending_confirm ? 33 : 57; character=(x-224)>>5; column=(x-224)>>1; row=(y-56)>>1; text_on=1;
            end else if(y>=216 && y<248 && x>=256 && x<384) begin
                message=pending_confirm ? 34:35; character=(x-256)>>5; column=(x-256)>>1;row=(y-216)>>1;text_on=1;
            end else if(y>=272 && y<288 && x>=(pending_confirm ? 200:216) && x<440) begin
                message=pending_confirm ? 58:59;
                character=(x-(pending_confirm ? 200:216))>>4;
                column=x-(pending_confirm ? 200:216);row=y-272;text_on=1;
                text_color=24'hffd166;
            end else if(y>=320 && y<336 && x>=(pending_confirm ? 208:176) && x<464) begin
                message=pending_confirm ? 60:61;
                character=(x-(pending_confirm ? 208:176))>>4;
                column=x-(pending_confirm ? 208:176);row=y-320;text_on=1;
            end else if(y>=296 && y<312 && x>=288 && x<352) begin
                message=scene_mode==2 ? 39+event_type:26+event_type;
                character=(x-288)>>4;column=x-288;row=y-296;text_on=1;
            end else if(y>=368 && y<384 && x>=272 && x<368) begin
                message=36; character=(x-272)>>4;column=x-272;row=y-368;text_on=1;
            end else if(y>=344 && y<360 && x>=(pending_confirm ? 200:208) && x<440) begin
                message=pending_confirm ? 74:75;
                character=(x-(pending_confirm ? 200:208))>>4;
                column=x-(pending_confirm ? 200:208);row=y-344;text_on=1;
                text_color=24'hffd166;
            end else if(y>=400 && y<416 && x>=(pending_confirm ? 120:136) && x<520) begin
                message=pending_confirm ? 76:77;
                character=(x-(pending_confirm ? 120:136))>>4;
                column=x-(pending_confirm ? 120:136);row=y-400;text_on=1;
            end
        end else if(drill_report) begin
            base=24'h10263d;
            if(y>=48 && y<96) base=24'h164b70;
            if(y>=56 && y<88 && x>=176 && x<464) begin
                message=83;character=(x-176)>>5;column=(x-176)>>1;row=(y-56)>>1;text_on=1;
            end else if(y>=136 && y<200 && x>=272 && x<368) begin
                message=25;row=(y-136)>>2;text_on=1;text_color=GREEN;
                character=x<304 ? drill_score/100:x<336 ? (drill_score/10)%10:drill_score%10;
                column=(x-(x<304?272:x<336?304:336))>>1;
                if(x<304 && drill_score<100) text_on=0;
            end else if(y>=224 && y<240) begin
                row=y-224;
                if(x>=80 && x<176) begin message=84;character=(x-80)>>4;column=x-80;text_on=1;end
                else if(x>=208 && x<256) begin message=25;character=x<224 ? drill_confirm_seconds/100:x<240 ? (drill_confirm_seconds/10)%10:drill_confirm_seconds%10;column=x-208;text_on=1;end
                else if(x>=256 && x<272) begin message=24;character=2;column=x-256;text_on=1;end
                else if(x>=336 && x<432) begin message=85;character=(x-336)>>4;column=x-336;text_on=1;end
                else if(x>=464 && x<512) begin message=25;character=x<480 ? drill_ack_seconds/100:x<496 ? (drill_ack_seconds/10)%10:drill_ack_seconds%10;column=x-464;text_on=1;end
                else if(x>=512 && x<528) begin message=24;character=2;column=x-512;text_on=1;end
            end else if(y>=272 && y<288) begin
                row=y-272;
                if(x>=80 && x<176) begin message=86;character=(x-80)>>4;column=x-80;text_on=1;end
                else if(x>=208 && x<256) begin message=25;character=x<224 ? drill_total_seconds/100:x<240 ? (drill_total_seconds/10)%10:drill_total_seconds%10;column=x-208;text_on=1;end
                else if(x>=256 && x<272) begin message=24;character=2;column=x-256;text_on=1;end
                else if(x>=336 && x<432) begin message=87;character=(x-336)>>4;column=x-336;text_on=1;end
                else if(x>=464 && x<480) begin message=25;character=drill_route_changes>9 ? 9:drill_route_changes;column=x-464;text_on=1;end
            end else if(y>=320 && y<336) begin
                row=y-320;
                if(x>=80 && x<176) begin message=88;character=(x-80)>>4;column=x-80;text_on=1;end
                else if(x>=208 && x<224) begin message=drill_corrected ? 96:94;character=0;column=x-208;text_on=1;end
            end else if(y>=368 && y<384 && x>=304 && x<352) begin
                message=drill_score>=90 ? 89:drill_score>=75 ? 90:91;
                character=(x-304)>>4;column=x-304;row=y-368;text_on=1;text_color=24'hffd166;
            end
        end else if(view==1) begin
            if(block_rect) base=hazard_mask[block_zone] ?
                (blink ? RED:24'h9c2338):24'h203b53;
            // White exclamation marks identify hazards without relying on red/green.
            if(block_rect && hazard_mask[block_zone] &&
               ((x>=240 && x<248 || x>=520 && x<528) &&
                (y>=152 && y<180 || y>=188 && y<196 || y>=296 && y<324 || y>=332 && y<340))) base=WHITE;
            if(corridor) base=24'h16533e;
            if(arrow) base=GREEN;
            if(x>=314 && x<326 && y>=238 && y<250) base=24'hffd166;
            // Exit boxes: red means unavailable. Both closed removes all arrows.
            if(y>=224 && y<264 && (x>=16 && x<80 || x>=560 && x<624))
                base=(x<320 ? exits_open[0]:exits_open[1]) ? 24'h14764e:24'h9c2338;
            // Explicit X marks keep a closed exit identifiable without color.
            if(y>=230 && y<258 &&
               ((!exits_open[0] && x>=34 && x<62 &&
                 (x+244>=y+46 && x+244<=y+50 || x+y>=290 && x+y<=294)) ||
                (!exits_open[1] && x>=578 && x<606 &&
                 (x-y>=346 && x-y<=350 || x+y>=834 && x+y<=838)))) base=WHITE;
            if(y>=56 && y<88 && x>=176 && x<464) begin
                message=scene_mode==2'd2 ? 38 : scene_mode==2'd1 ? 37 : 32;
                character=(x-176)>>5;column=(x-176)>>1;row=(y-56)>>1;text_on=1;
            end else if(route_pending && y>=88 && y<104 && x>=176 && x<464) begin
                message=78;character=(x-176)>>4;column=x-176;row=y-88;text_on=1;text_color=24'hffd166;
            end else if(y>=104 && y<120 && x>=96 && x<272) begin
                message=1;character=(x-96)>>4;column=x-96;row=y-104;text_on=x<160;
                if(x>=192 && x<240) begin
                    text_on=1;column=x-192;character=(x-192)>>4;
                    case(hazard_mask)
                        4'b0101:message=97;
                        4'b1010:message=98;
                        4'b1111:message=99;
                        default:begin message=25;character=10+zone;text_on=x<208;end
                    endcase
                end
            end else if(y>=104 && y<120 && x>=376 && x<520) begin
                row=y-104;text_on=1;
                if(x<408) begin message=24;character=(x-376)>>4;column=x-376;end
                else begin
                    message=25;column=x-408;
                    if(x<424) character=elapsed/100;
                    else if(x<440) character=(elapsed/10)%10;
                    else if(x<456) character=elapsed%10;
                    else begin text_on=0;end
                end
            end else if(y>=168 && y<184 && x>=168 && x<184 || y>=168 && y<184 && x>=448 && x<464 ||
                        y>=312 && y<328 && x>=168 && x<184 || y>=312 && y<328 && x>=448 && x<464) begin
                message=25;character=10+block_zone;row=y>=240 ? y-312:y-168;
                column=x>=320 ? x-448:x-168;text_on=1;
            end else if(y>=120 && y<136 && x>=224 && x<416) begin
                row=y-120;text_on=1;
                if(x<320) begin message=80;character=(x-224)>>4;column=x-224;end
                else if(recommended_exit!=0 && x<368) begin
                    message=recommended_exit==1 ? 2:3;character=(x-320)>>4;column=x-320;
                end else if(recommended_exit==0 && x<416) begin
                    message=21;character=(x-320)>>4;column=x-320;
                end else text_on=0;
            end else if(y>=216 && y<232 && x>=272 && x<368) begin
                message=21;character=(x-272)>>4;row=y-216;text_on=1;
            end else if(y>=264 && y<280 && (x>=16 && x<64 || x>=576 && x<624)) begin
                message=x<320 ? 2:3;character=x<320 ? (x-16)>>4:(x-576)>>4;row=y-264;text_on=1;
            end else if(y>=376 && y<408 && x>=64 && x<576) begin
                message=exits_open==0 ? 4:exits_open[0] ? 6:7;
                character=(x-64)>>5;column=(x-64)>>1;row=(y-376)>>1;text_on=1;
                text_color=exits_open==0 ? RED:GREEN;
            end else if(route_pending && y>=360 && y<376 && x>=176 && x<464) begin
                message=79;character=(x-176)>>4;column=x-176;row=y-360;text_on=1;text_color=24'hffd166;
            end else if(y>=416 && y<432 && x>=32 && x<608) begin
                message=5;character=(x-32)>>4;row=y-416;text_on=1;
                text_color=24'hffd166;
            end
        end else if(view==0 && scene_mode==2 && emergency) begin
            // Mall event cards are generated by logic, never misleading flood/earthquake BMPs.
            if(y>=104 && y<200 && x>=272 && x<368 &&
                (x>=320-(y-104)/2 && x<=320+(y-104)/2)) base=24'hffd166;
            if(x>=316 && x<324 && (y>=144 && y<172 || y>=180 && y<188)) base=BG;
            if(y>=216 && y<248 && x>=256 && x<384) begin
                message=39+event_type;character=(x-256)>>5;column=(x-256)>>1;row=(y-216)>>1;text_on=1;
            end else if(y>=272 && y<304 && x>=mall_primary_start && x<608) begin
                message=44+{event_type,1'b0};character=(x-mall_primary_start)>>5;column=(x-mall_primary_start)>>1;row=(y-272)>>1;text_on=1;
            end else if(y>=320 && y<336 && x>=mall_secondary_start && x<608) begin
                message=45+{event_type,1'b0};character=(x-mall_secondary_start)>>4;column=x-mall_secondary_start;row=y-320;text_on=1;
            end else if(y>=352 && y<368 && x>=mall_english_start && x<608) begin
                message=62+event_type;character=(x-mall_english_start)>>4;column=x-mall_english_start;row=y-352;text_on=1;
                text_color=24'hffd166;
            end else if(y>=384 && y<400 && x>=mall_action_start && x<608) begin
                message=event_type==0 ? 66:event_type==3 ? 68:event_type==2 ? 73:67;
                character=(x-mall_action_start)>>4;column=x-mall_action_start;row=y-384;text_on=1;
            end else if(y>=416 && y<432 && x>=32 && x<608) begin
                message=5;character=(x-32)>>4;row=y-416;text_on=1;text_color=24'hffd166;
            end
        end else if(view==2) begin
            if(y>=56 && y<88 && x>=192 && x<448) begin
                message=scene_mode==2'd2 ? 43 : scene_mode==2'd1 ? 37 : 9;
                character=(x-192)>>5;column=(x-192)>>1;row=(y-56)>>1;text_on=1;
            end else if(y>=112 && y<272 && x>=96 && x<544 && (y-112)%32<16) begin
                diagnostic_row=(y-112)>>5;row=(y-112)&15;
                message=10+diagnostic_row;
                character=(x-96)>>4;text_on=x<272;
                if(x>=320) begin
                    case(diagnostic_row)
                        0:digit={3'd0,clock_ok};1:digit={3'd0,memory_ok};2:digit={3'd0,card_ok};
                        3:digit={1'd0,image_verified_count};4:digit={1'd0,audio_verified_count};
                        default:digit=0;
                    endcase
                    if(diagnostic_row<5) begin
                        message=25;column=x-320;
                        if(x<336) begin character=digit;text_on=1;end
                        else if(diagnostic_row>=3 && x<352) begin character=20;text_on=1;end
                        else if(diagnostic_row>=3 && x<368) begin character=diagnostic_row==3 ? 6:4;text_on=1;end
                        else text_on=0;
                    end
                    else text_on=0;
                end
            end else if(y>=280 && y<296 && x>=80 && x<560) begin
                message=16;row=y-280;
                if(x<112) begin character=(x-80)>>4;text_on=1;end
                else if(x>=224 && x<256) begin character=3+((x-224)>>4);text_on=1;end
                else if(x>=320 && x<352) begin character=6+((x-320)>>4);text_on=1;end
                else if(x>=480 && x<512) begin character=9+((x-480)>>4);text_on=1;end
            end else if(y>=304 && y<320) begin
                row=y-304;
                if(x>=80 && x<144) begin
                    if(emergency) begin
                        message=scene_mode==2'd2 ? 39+event_type : 26+event_type;
                        character=(x-80)>>4;text_on=1;
                    end
                    else if(x<112) begin message=25;character=21;text_on=1;end
                end else if(x>=224 && x<272) begin
                    if(emergency && (hazard_mask==5 || hazard_mask==10 || hazard_mask==15)) begin
                        message=hazard_mask==5 ? 97:hazard_mask==10 ? 98:99;
                        character=(x-224)>>4;text_on=1;
                    end
                    else if(emergency && x<240) begin message=25;character=10+zone;text_on=1;end
                    else if(!emergency) begin message=25;character=21;text_on=x<240;end
                end else if(x>=320 && x<384) begin
                    if(emergency) begin message=acknowledged ? 18:17;character=(x-320)>>4;text_on=1;end
                    else if(x<352) begin message=25;character=21;text_on=1;end
                end else if(x>=480 && x<528) begin
                    message=25;text_on=1;
                    if(emergency) character=x<496 ? elapsed/100:x<512 ? (elapsed/10)%10:elapsed%10;
                    else begin character=21;text_on=x<496;end
                end else if(x>=528 && x<544 && emergency) begin
                    message=24;character=2;text_on=1;
                end
            end else if(y>=336 && y<352 && x>=96 && x<544) begin
                message=asset_failed ? 82 : fallback_active ? 8:81;
                character=(x-96)>>4;row=y-320;text_on=1;
                row=y-336;
            end else if(y>=368 && y<384 && x>=96 && x<544) begin
                message=30;character=(x-96)>>4;row=y-368;text_on=1;
            end else if(y>=400 && y<416 && x>=96 && x<544) begin
                message=20;character=(x-96)>>4;row=y-400;text_on=1;
            end
        end else if(view==3) begin
            if(y>=56 && y<88 && x>=80 && x<560) begin
                message=15;character=(x-80)>>5;column=(x-80)>>1;row=(y-56)>>1;text_on=1;
            end else if(y>=112 && y<128 && x>=80 && x<560) begin
                // Align each heading with the corresponding record column.
                message=16;row=y-112;
                if(x<112) begin character=(x-80)>>4;text_on=1;end
                else if(x>=224 && x<256) begin character=3+((x-224)>>4);text_on=1;end
                else if(x>=320 && x<352) begin character=6+((x-320)>>4);text_on=1;end
                else if(x>=480 && x<512) begin character=9+((x-480)>>4);text_on=1;end
            end else if(y>=160 && y<400 && (y-160)%64<16) begin
                record_row=(y-160)/64;
                case(record_row) 0:record=history[16:0];1:record=history[33:17];2:record=history[50:34];3:record=history[67:51];endcase
                record_scene=history_scene[record_row*2 +: 2];
                seconds_value=record[9:0];row=(y-160)%64;text_on=record_row<history_count;
                if(x>=80 && x<144) begin
                    message=record_scene==2'd2 ? 39+record[16:15] : 26+record[16:15];
                    character=(x-80)>>4;
                end
                else if(x>=224 && x<272 && record[14]) begin
                    message=record[13:12]==1 ? 97:record[13:12]==2 ? 98:99;character=(x-224)>>4;
                end
                else if(x>=224 && x<240) begin message=25;character=10+record[13:12];end
                else if(x>=320 && x<384) begin message=record[11:10]==3 ? 31:17+record[11:10];character=(x-320)>>4;end
                else if(x>=480 && x<528) begin
                    message=25;character=x<496 ? seconds_value/100:x<512 ? (seconds_value/10)%10:seconds_value%10;
                end else if(x>=528 && x<544) begin
                    message=24;character=2;
                end else text_on=0;
            end else if(y>=400 && y<416 && x>=96 && x<544) begin
                message=20;character=(x-96)>>4;row=y-400;text_on=1;
            end
        end
        if(border) begin base=blink ? RED:24'hffffff;text_on=0;end
    end
    wire [15:0] dots;
    terminal_safety_font u_font(.clk(clk),.message(message),.character(character),.row(row),.dots(dots));
    reg [3:0] column_q;
    reg text_q;
    reg [23:0] base_q,color_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin draw<=0;column_q<=0;text_q<=0;base_q<=0;color_q<=0;end
        else begin
            draw<=level_badge || audio_pixel || scene_strip || mall_heading || alert_ticker || report_footer || confirmation_area || border || enabled && content;
            column_q<=column;text_q<=text_on;base_q<=base;color_q<=text_color;
        end
    end
    always @* rgb_out=text_q && dots[15-column_q] ? color_q:base_q;
endmodule
