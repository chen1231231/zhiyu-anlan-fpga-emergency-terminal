`timescale 1ns/1ps
// All command/control state is in the 25 MHz pixel domain. Event acknowledgement
// silences sound; only a matching CLEAR removes a warning. UART is 115200 8N1.
module terminal_control #(
    parameter integer CLOCK_HZ=25000000,
    parameter integer UART_DIV=217,
    parameter integer PERIOD_FRAMES=300
) (
    input wire clk, rst_n, uart_rx,
    output wire uart_tx,
    input wire next_press, auto_ack_press, trigger_hold, clear_hold, scene_press,
    input wire brightness_press, contrast_hold,
    input wire sensor_trigger,
    input wire frame_start,
    input wire [5:0] available,
    input wire plan_valid,
    input wire [29:0] plan_data,
    output reg [2:0] active_index,
    output reg image_ready, emergency, acknowledged, auto_enabled,
    output reg [15:0] event_id,
    // 0=校园应急，1=疏散演练，2=商场应急
    output reg [1:0] scene_mode,
    output reg [1:0] event_type, selected_type, priority_level,
    output reg [2:0] brightness_level, contrast_level,
    output reg [2:0] volume_level,
    output reg [1:0] adjust_menu,
    output reg [4:0] reveal_step,
    output reg audio_test,
    output reg pending_confirm,
    output reg clear_pending,
    output wire alarm_enable
);
    reg normal_index;
    reg [1:0] demo_type;
    reg [15:0] local_id;
    reg [15:0] frames;
    reg normal_target;
    reg displayed;
    reg [7:0] result;
    reg plan_valid_q;
    wire [4:0] plan_normal_seconds=plan_data[4:0];
    wire [2:0] plan_default_volume=plan_data[11:9];
    wire [1:0] plan_default_scene=plan_data[13:12];
    wire [7:0] plan_priorities=plan_data[21:14];
    wire [1:0] planned_priority=selected_type==0 ? plan_priorities[1:0] :
                                selected_type==1 ? plan_priorities[3:2] :
                                selected_type==2 ? plan_priorities[5:4] : plan_priorities[7:6];
    wire [15:0] normal_period_frames=plan_valid ?
        (({11'd0,plan_normal_seconds}<<6)-({11'd0,plan_normal_seconds}<<2)) : PERIOD_FRAMES;
    // 校园与演练使用相同事件素材，仅切换疏散图标题。
    // 商场图文卡由叠加层生成，底层继续复用现有 bank。
    wire [2:0] emergency_target =
        scene_mode==2'd2 ? (event_type==2'd0 ? 3'd2 :
                            event_type==2'd1 ? 3'd5 :
                            event_type==2'd2 ? 3'd1 : 3'd4) :
        ({1'b0,event_type}+3'd2);
    wire [2:0] target = emergency ? emergency_target : {2'b0,normal_target};
    // Start the alert as soon as an event is accepted.  Waiting for the
    // emergency bitmap to finish loading made the audio appear dead while
    // the background SD-card ingest was still in progress.
    assign alarm_enable = emergency && !acknowledged;

    // Receive one byte, validate the middle of the start bit and the stop bit.
    reg rx_s1, rx_s2;
    reg [1:0] rx_state;
    reg [15:0] rx_count;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift, rx_byte;
    reg rx_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_s1<=1; rx_s2<=1; rx_state<=0; rx_count<=0; rx_bit<=0; rx_shift<=0; rx_byte<=0; rx_valid<=0; end
        else begin
            rx_s1<=uart_rx; rx_s2<=rx_s1; rx_valid<=0;
            case(rx_state)
                0: if (!rx_s2) begin rx_state<=1; rx_count<=UART_DIV/2; end
                1: if (rx_count!=0) rx_count<=rx_count-1'b1;
                   else if (!rx_s2) begin rx_state<=2; rx_count<=UART_DIV-1; rx_bit<=0; end
                   else rx_state<=0;
                2: if (rx_count!=0) rx_count<=rx_count-1'b1;
                   else begin
                       rx_shift[rx_bit]<=rx_s2; rx_count<=UART_DIV-1;
                       if (rx_bit==7) rx_state<=3; else rx_bit<=rx_bit+1'b1;
                   end
                3: if (rx_count!=0) rx_count<=rx_count-1'b1;
                   else begin rx_state<=0; if(rx_s2) begin rx_byte<=rx_shift; rx_valid<=1; end end
            endcase
        end
    end
    reg [3:0] packet_pos;
    reg [7:0] opcode, cmd_type, cmd_level, checksum;
    reg [15:0] cmd_id;
    reg command;
    reg [20:0] rx_timeout;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin packet_pos<=0; opcode<=0; cmd_type<=0; cmd_level<=0; cmd_id<=0; checksum<=0; command<=0; rx_timeout<=0; end
        else begin
            command<=0;
            if (packet_pos!=0) begin
                if(rx_timeout==CLOCK_HZ/20) begin packet_pos<=0; rx_timeout<=0; end
                else rx_timeout<=rx_timeout+1'b1;
            end
            if(rx_valid) begin
                rx_timeout<=0;
                case(packet_pos)
                    0: if(rx_byte==8'haa) packet_pos<=1;
                    1: if(rx_byte==8'h55) begin packet_pos<=2; checksum<=0; end
                       else packet_pos<=rx_byte==8'haa ? 1:0;
                    2: begin opcode<=rx_byte; checksum<=rx_byte; packet_pos<=3; end
                    3: begin cmd_id[7:0]<=rx_byte; checksum<=checksum^rx_byte; packet_pos<=4; end
                    4: begin cmd_id[15:8]<=rx_byte; checksum<=checksum^rx_byte; packet_pos<=5; end
                    5: begin cmd_type<=rx_byte; checksum<=checksum^rx_byte; packet_pos<=6; end
                    6: begin cmd_level<=rx_byte; checksum<=checksum^rx_byte; packet_pos<=7; end
                    7: begin if(rx_byte==checksum) command<=1; packet_pos<=0; end
                    default: packet_pos<=0;
                endcase
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active_index<=0; image_ready<=0; emergency<=0; acknowledged<=0;
            auto_enabled<=1; event_id<=0; scene_mode<=0; event_type<=0; selected_type<=0; priority_level<=0;
            brightness_level<=0; contrast_level<=0; volume_level<=3'd2;
            adjust_menu<=0; reveal_step<=20; pending_confirm<=0; clear_pending<=0;
            normal_index<=0; normal_target<=0; demo_type<=0; local_id<=16'h8000;
            frames<=0; displayed<=0; result<=0; audio_test<=0;
            plan_valid_q<=0;
        end else begin
            plan_valid_q<=plan_valid;
            if(plan_valid && !plan_valid_q && !emergency && !pending_confirm) begin
                scene_mode<=plan_default_scene;
                volume_level<=plan_default_volume;
                selected_type<=0;
            end
            // Confirmation flags are one-shot UI state; the event itself
            // remains locked until the operator confirms it explicitly.
            if (!emergency && !pending_confirm) clear_pending<=0;
            if(frame_start) begin
                active_index<=target; image_ready<=available[target];
                if(emergency && active_index==target) displayed<=1;
                if(emergency) begin reveal_step<=20; frames<=0; end
                else begin
                    if(normal_index!=normal_target) begin normal_index<=normal_target; reveal_step<=0; end
                    else if(reveal_step<20) reveal_step<=reveal_step+1'b1;
                    if(auto_enabled) begin
                        if(frames==normal_period_frames-1) begin
                            frames<=0;
                            if(available[normal_target ? 0:1]) normal_target<=~normal_target;
                        end else frames<=frames+1'b1;
                    end
                end
            end
            // KEY4 short adjusts the selected item; KEY4 long switches the
            // item in the small on-screen settings menu.  All three settings
            // use five levels: level 0 is full, each press removes one bar.
            if(brightness_press) begin
                case(adjust_menu)
                    2'd0: brightness_level <= brightness_level >= 3'd4 ? 3'd0 : brightness_level + 1'b1;
                    2'd1: contrast_level <= contrast_level >= 3'd4 ? 3'd0 : contrast_level + 1'b1;
                    default: volume_level <= volume_level >= 3'd4 ? 3'd0 : volume_level + 1'b1;
                endcase
            end
            if(contrast_hold) begin
                adjust_menu<=adjust_menu==2 ? 0 : adjust_menu+1'b1;
            end
            // KEY2 long changes auto/manual in normal and emergency operation.
            if(trigger_hold) auto_enabled<=~auto_enabled;
            if(!emergency) begin
                // Normal mode: KEY2 short changes the normal page, KEY2 long
                // changes auto/manual, KEY3 long selects an event, and KEY3
                // short publishes that selected event.
                if(next_press) begin normal_target<=~normal_target; frames<=0; end
                // The KEY2+KEY3 short chord changes scene. Event selection is
                // reset so a mall mode can never inherit a campus event label.
                if(scene_press) begin
                    scene_mode<=scene_mode==2'd2 ? 0 : scene_mode+1'b1;
                    selected_type<=0;
                    pending_confirm<=0;
                end
                else if(clear_hold) begin
                    pending_confirm<=0;
                    // KEY3 long selects only within the current scene.
                    selected_type<=selected_type==2'd3 ? 0 : selected_type+1'b1;
                end
                else if(auto_ack_press || sensor_trigger) begin
                    if (pending_confirm) begin
                        emergency<=1; pending_confirm<=0; acknowledged<=0; displayed<=0;
                        event_id<=local_id; local_id<=local_id+1'b1;
                        event_type<=selected_type;
                        priority_level<=plan_valid ? planned_priority : 2;
                        volume_level<=plan_valid ? plan_default_volume : 3'd2; result<=0;
                    end else begin
                        pending_confirm<=1;
                    end
                end
            end else if(auto_ack_press) acknowledged<=1;
            if(clear_hold && emergency) begin
                if (clear_pending) begin
                    emergency<=0; acknowledged<=0; displayed<=0; clear_pending<=0;
                end else clear_pending<=1;
            end
            if(command) begin
                result<=0;
                case(opcode)
                    1: if(cmd_type>3 || cmd_level>3 || cmd_id==0) result<=1;
                       else if(cmd_id==event_id) begin
                           // Tombstone: retransmitting a cleared event cannot reactivate it.
                           if(!emergency || cmd_type[1:0]!=event_type || cmd_level[1:0]!=priority_level) result<=2;
                       end else if(emergency && cmd_level[1:0]<priority_level) result<=3;
                       else begin
                           emergency<=1; acknowledged<=0; displayed<=0;
                           pending_confirm<=0; clear_pending<=0;
                           event_id<=cmd_id; event_type<=cmd_type[1:0]; selected_type<=cmd_type[1:0]; priority_level<=cmd_level[1:0];
                           volume_level<=plan_valid ? plan_default_volume : 3'd2;
                       end
                    2: if(emergency && cmd_id==event_id) acknowledged<=1; else result<=4;
                    3: if(emergency && cmd_id==event_id) begin emergency<=0; acknowledged<=0; displayed<=0; clear_pending<=0; pending_confirm<=0; end
                       else result<=4;
                    4: ; // Query: next periodic snapshot returns current state.
                    5: if(cmd_type<=1) audio_test<=cmd_type[0]; else result<=1;
                    default: result<=5;
                endcase
            end
        end
    end

    // Immutable status snapshot repeated every 100 ms. Latest state persists,
    // so a short UART interruption cannot silently lose an event's final state.
    // AA 55 80 IDlo IDhi TYPE FLAGS RESULT XOR(bytes2..7)
    reg [21:0] report_timer;
    reg [71:0] report;
    reg [3:0] tx_pos;
    reg reporting, tx_start;
    reg [7:0] tx_data;
    wire tx_busy, tx_done;
    wire [7:0] flags={2'b0,auto_enabled,image_ready,acknowledged,displayed,emergency,event_id!=0};
    uart_tx_byte #(.CLKS_PER_BIT(UART_DIV)) u_tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),.tx(uart_tx),.busy(tx_busy),.done(tx_done));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin report_timer<=0; report<=0; tx_pos<=0; reporting<=0; tx_start<=0; tx_data<=0; end
        else begin
            tx_start<=0;
            if(report_timer==CLOCK_HZ/10-1) begin
                report_timer<=0;
                if(!reporting) begin
                    report<={8'haa,8'h55,8'h80,event_id[7:0],event_id[15:8],6'd0,event_type,flags,result,
                        (8'h80^event_id[7:0]^event_id[15:8]^{6'd0,event_type}^flags^result)};
                    reporting<=1; tx_pos<=0;
                end
            end else report_timer<=report_timer+1'b1;
            if(reporting && !tx_busy && !tx_start) begin
                tx_data<=report[71:64]; report<={report[63:0],8'd0}; tx_start<=1;
                if(tx_pos==8) reporting<=0; else tx_pos<=tx_pos+1'b1;
            end
        end
    end
endmodule
