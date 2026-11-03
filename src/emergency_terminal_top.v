`timescale 1ns/1ps

// Emergency terminal V1: six image banks with progressive background loading.
// KEY2: page short / auto-manual long; KEY3: publish/select/ack/clear; KEY4: adjust/select.
// UART: event commands and periodic status snapshots. HDMI output uses port B.
module emergency_terminal_top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire       key2_n,
    input  wire       key3_n,
    input  wire       key4_n,
    input wire        uart_rx_i,
    output wire       uart_tx_o,
    output wire       sd_cs_n,
    output wire       sd_sclk,
    output wire       sd_mosi,
    input  wire       sd_miso,
    input  wire       flash_miso,
    output wire       flash_cs_n,
    output wire       flash_sclk,
    output wire       flash_mosi,
    output wire       flash_wp_n,
    output wire       flash_hold_n,
    output wire       HDMI_CLK_P,
    output wire       HDMI_D2_P,
    output wire       HDMI_D1_P,
    output wire       HDMI_D0_P,
    output wire       HDMI_DDC_SCL,
    inout  wire       HDMI_DDC_SDA,
    input  wire [3:0] sw_i,
    output wire [5:0] seg_sel,
    output wire [7:0] seg_data,
    output wire [3:0] led
);
    wire mem_feedback_clk;
    wire mem_clk;
    wire mem_clk_shift;
    wire mem_locked;
    sys_pll u_mem_pll (
        .refclk(sys_clk), .reset(~sys_rst_n),
        .clk0_out(mem_feedback_clk), .clk1_out(mem_clk),
        .clk2_out(mem_clk_shift), .locked(mem_locked)
    );

    wire pixel_clk_5x;
    wire pixel_clk;
    wire video_locked;
    clk_wize u_video_pll (
        .refclk(sys_clk), .reset(1'b0),
        .clk0_out(pixel_clk), .clk1_out(pixel_clk_5x),
        .locked(video_locked)
    );

    wire mem_rst_n;
    wire pix_rst_n;
    wire pix_5x_rst_n;
    wire ctrl_rst_n;
    reset_sync u_mem_reset (
        .clk(mem_clk), .ext_rst_n(sys_rst_n & mem_locked),
        .rst_n_sync(mem_rst_n)
    );
    reset_sync u_pix_reset (
        .clk(pixel_clk), .ext_rst_n(sys_rst_n & video_locked),
        .rst_n_sync(pix_rst_n)
    );
    reset_sync u_pix_5x_reset (
        .clk(pixel_clk_5x), .ext_rst_n(sys_rst_n & video_locked),
        .rst_n_sync(pix_5x_rst_n)
    );
    reset_sync u_ctrl_reset (
        .clk(sys_clk), .ext_rst_n(sys_rst_n & video_locked),
        .rst_n_sync(ctrl_rst_n)
    );

    wire sdram_init_done;
    wire sdram_refresh_active;
    wire sdram_busy;
    wire ingest_app_wr_en;
    wire [20:0] ingest_app_wr_addr;
    wire [3:0] ingest_app_wr_mask;
    wire [31:0] ingest_app_wr_data;
    wire player_app_rd_en;
    wire [20:0] player_app_rd_addr;
    wire sdram_rd_valid;
    wire [31:0] sdram_rd_data;
    wire ingest_burst_request, ingest_burst_busy, ingest_burst_grant;
    wire player_burst_request, player_burst_busy, player_burst_grant;
    wire memory_idle;

    media_sdram_arbiter u_memory_arbiter (
        .clk(mem_clk), .rst_n(mem_rst_n),
        .controller_busy(sdram_busy), .refresh_active(sdram_refresh_active),
        .read_request(player_burst_request), .read_busy(player_burst_busy),
        .write_request(ingest_burst_request), .write_busy(ingest_burst_busy),
        .read_grant(player_burst_grant), .write_grant(ingest_burst_grant),
        .idle(memory_idle)
    );

    sdram u_sdram (
        .Clk(mem_clk), .Clk_sft(mem_clk_shift), .Rst(~mem_rst_n),
        .Sdr_init_done(sdram_init_done),
        .Sdr_init_ref_vld(sdram_refresh_active), .Sdr_busy(sdram_busy),
        .App_wr_en(ingest_app_wr_en), .App_wr_addr(ingest_app_wr_addr),
        .App_wr_dm(ingest_app_wr_mask), .App_wr_din(ingest_app_wr_data),
        .App_rd_en(player_app_rd_en), .App_rd_addr(player_app_rd_addr),
        .Sdr_rd_en(sdram_rd_valid), .Sdr_rd_dout(sdram_rd_data)
    );

    wire ingest_start;
    wire ingest_busy;
    wire ingest_done;
    wire [2:0] ingest_error_stage;
    wire [7:0] ingest_error_code;
    wire [7:0] ingest_error_detail;
    wire card_ready;
    wire card_high_capacity;
    wire [5:0] resource_valid;
    wire [5:0] image_complete;
    wire [5:0] image_failed;
    wire [23:0] image_failure_codes;
    wire [5:0] image_crc_ok,image_crc_failed;
    wire [3:0] audio_resource_valid;
    wire [3:0] audio_crc_ok,audio_crc_failed;
    wire plan_valid_mem;
    wire plan_error_mem;
    wire [29:0] plan_data_mem;
    wire audio_file_start, audio_file_stop, audio_sector_admit;
    wire [1:0] audio_file_select;
    wire audio_file_busy, audio_file_done, audio_file_valid;
    wire [7:0] audio_file_byte, audio_file_error;
    wire [7:0] audio_player_error;
    wire recovery_active,media_healthy;
    wire retry_second_toggle_pix,retry_second_toggle_mem;
    reg retry_second_toggle_q;
    sync_2ff u_retry_second_sync(.clk(mem_clk),.rst_n(mem_rst_n),
        .async_in(retry_second_toggle_pix),.sync_out(retry_second_toggle_mem));
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if(!mem_rst_n) retry_second_toggle_q<=0;
        else retry_second_toggle_q<=retry_second_toggle_mem;
    end
    terminal_media_recovery u_media_recovery(
        .clk(mem_clk),.rst_n(mem_rst_n),.memory_ready(sdram_init_done),
        .ingest_busy(ingest_busy),.ingest_done(ingest_done),.ingest_error(ingest_error_code),
        .runtime_fault(media_healthy && (audio_file_error!=0 || audio_player_error!=0)),
        .retry_tick(retry_second_toggle_mem^retry_second_toggle_q),
        .ingest_start(ingest_start),.recovery_active(recovery_active),.media_healthy(media_healthy));
    media_storage_ingest_top #(.VERIFY_RELEASE_CRC(1)) u_storage_ingest (
        .clk(mem_clk), .rst_n(mem_rst_n), .start(ingest_start),
        .busy(ingest_busy), .done(ingest_done),
        .error_stage(ingest_error_stage), .error_code(ingest_error_code),
        .error_detail(ingest_error_detail), .card_ready(card_ready),
        .card_high_capacity(card_high_capacity),
        .resource_valid(resource_valid), .image_complete(image_complete),
        .image_failed(image_failed), .image_failure_codes(image_failure_codes),
        .image_crc_ok(image_crc_ok),.image_crc_failed(image_crc_failed),
        .audio_resource_valid(audio_resource_valid),
        .audio_crc_ok(audio_crc_ok),.audio_crc_failed(audio_crc_failed),
        .plan_valid(plan_valid_mem),.plan_error(plan_error_mem),.plan_data(plan_data_mem),
        .audio_file_start(audio_file_start), .audio_file_stop(audio_file_stop),
        .audio_file_select(audio_file_select), .audio_sector_admit(audio_sector_admit),
        .audio_file_busy(audio_file_busy), .audio_file_done(audio_file_done),
        .audio_file_valid(audio_file_valid), .audio_file_byte(audio_file_byte),
        .audio_file_error(audio_file_error),
        .controller_init_done(sdram_init_done),
        .controller_busy(sdram_busy), .refresh_active(sdram_refresh_active),
        .burst_grant(ingest_burst_grant), .burst_request(ingest_burst_request),
        .burst_busy(ingest_burst_busy),
        .app_wr_en(ingest_app_wr_en), .app_wr_addr(ingest_app_wr_addr),
        .app_wr_mask(ingest_app_wr_mask), .app_wr_data(ingest_app_wr_data),
        .sd_cs_n(sd_cs_n), .sd_sclk(sd_sclk),
        .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );

// Included by the mechanically derived top, after the proven storage wiring.
    assign flash_cs_n=1'b1;
    assign flash_sclk=1'b0;
    assign flash_mosi=1'b0;
    assign flash_wp_n=1'b1;
    assign flash_hold_n=1'b1;
    wire video_clk=pixel_clk;
    reg [5:0] safe_complete;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if(!mem_rst_n) safe_complete<=0;
        else begin
            if(memory_idle && !sdram_busy && !sdram_refresh_active) safe_complete<=safe_complete|(image_complete&image_crc_ok);
        end
    end
    wire plan_valid_pix;
    sync_2ff u_plan_valid_sync(.clk(pixel_clk),.rst_n(pix_rst_n),
        .async_in(plan_valid_mem),.sync_out(plan_valid_pix));
    reg [29:0] plan_data_pix;
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) plan_data_pix<=0;
        else if(!plan_valid_pix) plan_data_pix<=plan_data_mem;
    end
    wire [5:0] available;
    wire [5:0] failed_sync;
    wire [23:0] failure_codes;
    genvar gi;
    generate for(gi=0;gi<6;gi=gi+1) begin:g_available
        sync_2ff u_sync(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(safe_complete[gi]),.sync_out(available[gi]));
        sync_2ff u_fail(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(image_failed[gi]),.sync_out(failed_sync[gi]));
    end endgenerate
    generate for(gi=0;gi<24;gi=gi+1) begin:g_failure_codes
        sync_2ff u_code(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(image_failure_codes[gi]),.sync_out(failure_codes[gi]));
    end endgenerate
    wire k2_short,k2_long,k3_short,k3_long,k4_short,k4_long;
    wire k2_level,k3_level,key23_chord,key23_suppress;
    terminal_keys u_key2(.clk(pixel_clk),.rst_n(pix_rst_n),.key_n(key2_n),.short_press(k2_short),.long_press(k2_long),.pressed_level(k2_level));
    terminal_keys u_key3(.clk(pixel_clk),.rst_n(pix_rst_n),.key_n(key3_n),.short_press(k3_short),.long_press(k3_long),.pressed_level(k3_level));
    terminal_keys u_key4(.clk(pixel_clk),.rst_n(pix_rst_n),.key_n(key4_n),.short_press(k4_short),.long_press(k4_long),.pressed_level());
    terminal_key_chord u_key23(.clk(pixel_clk),.rst_n(pix_rst_n),
        .key_a_level(k2_level),.key_b_level(k3_level),.chord_press(key23_chord),
        .suppress_individual(key23_suppress));
    wire k2_short_action=k2_short && !key23_suppress;
    wire k3_short_action=k3_short && !key23_suppress;
    wire k2_long_action=k2_long && !key23_suppress;
    wire k3_long_action=k3_long && !key23_suppress;
    wire raw_hs,raw_vs,raw_de;
    wire [11:0] raw_x,raw_y;
    video_timing_ctrl u_timing(.pclk(pixel_clk),.rst_n(pix_rst_n),.hsync(raw_hs),.vsync(raw_vs),.de(raw_de),.x(raw_x),.y(raw_y));
    reg vs_q,reader_frame;
    wire frame_start=vs_q && !raw_vs;
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin vs_q<=1;reader_frame<=0; end
        else begin vs_q<=raw_vs;reader_frame<=frame_start; end
    end
    wire [2:0] active_index;
    wire image_ready,emergency,acknowledged,auto_enabled,alarm_enable,audio_test;
    wire [15:0] event_id;
    wire [1:0] scene_mode,selected_type;
    wire [2:0] volume_level;
    wire [1:0] event_type,priority_level;
    wire [2:0] brightness,contrast;
    wire [1:0] adjust_menu;
    wire pending_confirm,clear_pending;
    wire [4:0] reveal_step;
    wire sensor_trigger;
    wire [3:0] stable_sw;
    wire [1:0] safety_zone,safety_exits,safety_view;
    wire [3:0] safety_hazards;
    wire safety_block,safety_startup;
    wire [9:0] safety_elapsed;
    wire [67:0] safety_history;
    wire [7:0] safety_history_scene;
    wire [2:0] history_count;
    wire [1:0] alert_level,recommended_exit;
    wire [6:0] route_score,drill_score;
    wire route_pending,drill_report,drill_corrected;
    wire [7:0] drill_confirm_seconds;
    wire [9:0] drill_ack_seconds,drill_total_seconds;
    wire [3:0] drill_route_changes;
    terminal_safety u_safety(
        .clk(pixel_clk),.rst_n(pix_rst_n),.sw(sw_i),
        .emergency(emergency),.acknowledged(acknowledged),.event_id(event_id),.scene_mode(scene_mode),.event_type(event_type),
        .next_press(k2_short_action),.page_hold(key23_chord),.frame_start(frame_start),.auto_enabled(auto_enabled),
        .pending_confirm(pending_confirm),.operator_confirm(k3_short_action),
        .plan_valid(plan_valid_pix),.plan_emergency_seconds(plan_data_pix[8:5]),
        .sensor_trigger(sensor_trigger),.stable_sw(stable_sw),
        .zone(safety_zone),.extra_block(safety_block),.exits_open(safety_exits),.hazard_mask(safety_hazards),.view(safety_view),
        .elapsed(safety_elapsed),.history(safety_history),.history_scene(safety_history_scene),.history_count(history_count),
        .alert_level(alert_level),.route_pending(route_pending),.recommended_exit(recommended_exit),.route_score(route_score),
        .drill_report(drill_report),.drill_score(drill_score),.drill_confirm_seconds(drill_confirm_seconds),
        .drill_ack_seconds(drill_ack_seconds),.drill_total_seconds(drill_total_seconds),
        .drill_route_changes(drill_route_changes),.drill_corrected(drill_corrected),
        .second_toggle(retry_second_toggle_pix),.startup(safety_startup));
    terminal_control u_control(
        .clk(pixel_clk),.rst_n(pix_rst_n),.uart_rx(uart_rx_i),.uart_tx(uart_tx_o),
        .next_press(k2_short_action),.auto_ack_press(k3_short_action && !route_pending),.trigger_hold(k2_long_action),.clear_hold(k3_long_action),.scene_press(key23_chord),
        .brightness_press(k4_short),.contrast_hold(k4_long),.frame_start(frame_start),.available(available),
        .plan_valid(plan_valid_pix),.plan_data(plan_data_pix),
        .sensor_trigger(sensor_trigger),
        .active_index(active_index),.image_ready(image_ready),.emergency(emergency),.acknowledged(acknowledged),
        .auto_enabled(auto_enabled),.event_id(event_id),.scene_mode(scene_mode),.event_type(event_type),.selected_type(selected_type),.priority_level(priority_level),
        .brightness_level(brightness),.contrast_level(contrast),.volume_level(volume_level),.adjust_menu(adjust_menu),.reveal_step(reveal_step),
        .alarm_enable(alarm_enable),.audio_test(audio_test),.pending_confirm(pending_confirm),.clear_pending(clear_pending));
    wire reader_underflow,reader_pixel_valid;
    wire [23:0] reader_rgb;
    wire [7:0] reader_error;
    media_frame_reader u_reader(
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.controller_init_done(sdram_init_done),
        .controller_busy(sdram_busy),.refresh_active(sdram_refresh_active),
        .burst_grant(player_burst_grant),.burst_request(player_burst_request),.burst_busy(player_burst_busy),
        .app_rd_en(player_app_rd_en),.app_rd_addr(player_app_rd_addr),
        .sdram_rd_valid(sdram_rd_valid),.sdram_rd_data(sdram_rd_data),
        .pix_clk(pixel_clk),.pix_rst_n(pix_rst_n),.frame_start(reader_frame && image_ready),
        .active_index(active_index),.pixel_consume(raw_de && image_ready),
        .pixel_rgb(reader_rgb),.pixel_valid(reader_pixel_valid),.underflow(reader_underflow),
        .reader_busy(),.frame_read_done(),.reader_index(),.reader_error(reader_error));
    wire audio_sample_valid;
    wire signed [15:0] audio_sample_left,audio_sample_right,pcm_sample_left;
    wire pcm_starved,alarm_fallback;
    wire pcm_fault;
    wire audio_stream_underflow;
    wire recovery_pix;
    sync_2ff u_recovery_sync(.clk(pixel_clk),.rst_n(pix_rst_n),
        .async_in(recovery_active),.sync_out(recovery_pix));
    wire [7:0] volume_gain = volume_level == 3'd0 ? 8'd255 :
                             volume_level == 3'd1 ? 8'd192 :
                             volume_level == 3'd2 ? 8'd128 :
                             volume_level == 3'd3 ? 8'd64 : 8'd0;
    wire [1:0] player_event_type;
    terminal_plan_audio_select u_plan_audio_select(
        .scene_mode(scene_mode),.event_type(event_type),.plan_valid(plan_valid_pix),
        .audio_map(plan_data_pix[29:22]),.player_event_type(player_event_type));
    sync_2ff u_audio_fault_sync(.clk(pixel_clk),.rst_n(pix_rst_n),
        .async_in((audio_player_error!=0) || (audio_resource_valid==0) ||
                  (|audio_crc_failed) || recovery_active),.sync_out(pcm_fault));
    terminal_alarm_fallback u_fallback(.clk(pixel_clk),.rst_n(pix_rst_n),
        .sample_valid(audio_sample_valid),.alarm_enable(alarm_enable),.pcm_fault(pcm_fault),
        .underflow(pcm_starved),.volume_level(volume_level),.pcm(pcm_sample_left),
        .sample_out(audio_sample_left),.fallback_active(alarm_fallback));
    assign audio_sample_right=audio_sample_left;
    tf_pcm_audio_player u_audio_player(
        .mem_clk(mem_clk),.mem_rst_n(mem_rst_n),.pix_clk(video_clk),.pix_rst_n(pix_rst_n),
        .alarm_enable(alarm_enable && !recovery_pix),.audio_test(audio_test && !recovery_pix),
        // Mall crowding/power/escalator alerts must never announce earthquake/flood.
        .event_type(player_event_type),
        .volume(alarm_enable || audio_test ? volume_gain : 8'd0),
        // The FAT scan publishes audio metadata before the six image banks
        // finish loading.  Audio can therefore start during background ingest.
        .audio_available(audio_resource_valid),
        .file_start(audio_file_start),.file_stop(audio_file_stop),.file_select(audio_file_select),
        .sector_admit(audio_sector_admit),.file_busy(audio_file_busy),.file_done(audio_file_done),
        .file_valid(audio_file_valid),.file_byte(audio_file_byte),.file_error(audio_file_error),
        .sample_valid(audio_sample_valid),.sample_left(pcm_sample_left),.sample_right(),.pcm_starved(pcm_starved),
        .underflow(audio_stream_underflow),.player_error(audio_player_error));
    wire [23:0] video_rgb_sub,video_rgb_text,video_rgb_safety;
    wire video_hs_sub,video_vs_sub,video_de_sub;
    wire [9:0] video_x_sub;
    terminal_overlay u_overlay(.clk(pixel_clk),.rst_n(pix_rst_n),.hs(raw_hs),.vs(raw_vs),.de(raw_de),
        .x(raw_x[9:0]),.y(raw_y[9:0]),.rgb(reader_pixel_valid ? reader_rgb:24'd0),
        .page(active_index),.emergency(emergency),.acknowledged(acknowledged),.auto_enabled(auto_enabled),
        .image_ready(image_ready),.event_id(event_id),.brightness(brightness),.contrast(contrast),.volume_level(volume_level),.reveal_step(reveal_step),
        .content_override(emergency && (safety_view!=0 || scene_mode==2'd2) || safety_startup || pending_confirm || clear_pending || drill_report),
        .failure_reason(failed_sync[active_index] ? failure_codes[active_index*4 +: 4] : 4'd0),
        .available_mask(available),
        .hs_out(video_hs_sub),.vs_out(video_vs_sub),.de_out(video_de_sub),.x_out(video_x_sub),.rgb_out(video_rgb_text));
    // Both OSD engines register the same raw coordinates: no extra video latency.
    wire safety_draw;
    wire [3:0] audio_avail_pix;
    wire audio_verified_pix,asset_failed_pix;
    wire card_ok_pix,memory_ok_pix;
    terminal_safety_overlay u_safety_overlay(.clk(pixel_clk),.rst_n(pix_rst_n),
        .x(raw_x[9:0]),.y(raw_y[9:0]),.frame_start(frame_start),
        .enabled(emergency && (safety_view!=0 || scene_mode==2'd2) || safety_startup || pending_confirm || clear_pending || drill_report),
        .view(safety_startup ? 2'd2:safety_view),.zone(safety_zone),.exits_open(safety_exits),.hazard_mask(safety_hazards),
        .audio_active(alarm_enable),.pcm_valid(audio_sample_valid),.pcm_sample(audio_sample_left),
        .elapsed(safety_elapsed),.history(safety_history),.history_scene(safety_history_scene),.history_count(history_count),
        .emergency(emergency),.acknowledged(acknowledged),.pending_confirm(pending_confirm),.clear_pending(clear_pending),.auto_enabled(auto_enabled),.scene_mode(scene_mode),
        .alert_level(alert_level),.route_pending(route_pending),.recommended_exit(recommended_exit),.route_score(route_score),
        .drill_report(drill_report),.drill_score(drill_score),.drill_confirm_seconds(drill_confirm_seconds),
        .drill_ack_seconds(drill_ack_seconds),.drill_total_seconds(drill_total_seconds),
        .drill_route_changes(drill_route_changes),.drill_corrected(drill_corrected),
        .event_type(emergency ? event_type:selected_type),
        .available(available),.audio_available(audio_avail_pix),
        .audio_verified(audio_verified_pix),.asset_failed(asset_failed_pix),
        .card_ok(card_ok_pix),.memory_ok(memory_ok_pix),
        .clock_ok(1'b1),.fallback_active(alarm_fallback),
        .rgb_out(video_rgb_safety),.draw(safety_draw));
    sync_2ff u_card_status(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(card_ready),.sync_out(card_ok_pix));
    sync_2ff u_memory_status(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(sdram_init_done),.sync_out(memory_ok_pix));
    sync_2ff u_asset_verified(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(&audio_crc_ok),.sync_out(audio_verified_pix));
    sync_2ff u_asset_failed(.clk(pixel_clk),.rst_n(pix_rst_n),
        .async_in((|image_crc_failed)||(|audio_crc_failed)||recovery_active||
                  plan_error_mem),.sync_out(asset_failed_pix));
    generate for(gi=0;gi<4;gi=gi+1) begin:g_audio_status
        sync_2ff u_sync(.clk(pixel_clk),.rst_n(pix_rst_n),.async_in(audio_resource_valid[gi]),.sync_out(audio_avail_pix[gi]));
    end endgenerate
    assign video_rgb_sub=safety_draw ? video_rgb_safety:video_rgb_text;
    assign led={emergency,acknowledged,|available,mem_locked & video_locked};
    terminal_sevenseg #(.CLOCK_HZ(25000000)) u_sevenseg(
        .clk(pixel_clk), .rst_n(pix_rst_n), .emergency(emergency),
        .event_type(event_type), .selected_type(selected_type), .volume_level(volume_level),
        .brightness(brightness), .contrast(contrast), .adjust_menu(adjust_menu),
        .seg_sel(seg_sel), .seg_data(seg_data));
    wire axis_s_user;
    wire axis_s_valid;
    wire axis_s_last;
    wire [23:0] axis_s_data;
    video_rgb_to_axis_640x480 u_video_to_axis (
        .I_clk(video_clk), .I_rst(~pix_rst_n),
        .I_vs(video_vs_sub), .I_de(video_de_sub), .I_rgb(video_rgb_sub),
        .O_video_user(axis_s_user), .O_video_valid(axis_s_valid),
        .O_video_last(axis_s_last), .O_video_data(axis_s_data)
    );

    wire edid_read_trig;
    wire edid_read_valid;
    wire [7:0] edid_read_data;
    startup_pulse #(.CNT_MAX(20'd100000)) u_edid_startup (
        .I_clk(video_clk), .I_rst(~pix_rst_n), .O_pulse(edid_read_trig)
    );

    wire acr_valid;
    wire [19:0] acr_cts;
    wire [19:0] acr_n;
    audio_arc_calculate #(.ACR_N(6144)) u_audio_acr (
        .I_clk(video_clk), .I_rst(~pix_rst_n),
        .I_audio_valid(audio_sample_valid),
        .O_acr_valid(acr_valid), .O_acr_cts(acr_cts), .O_acr_n(acr_n)
    );

    wire hdmi_video_locked;
    wire [9:0] tmds_ch0_data;
    wire [9:0] tmds_ch1_data;
    wire [9:0] tmds_ch2_data;
    wire [9:0] tmds_clk_data;
    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"),
        .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
        .VTOTAL(525), .VSA(2), .VFP(10), .VBP(33), .VACTIVE(480),
        .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"), .VIDEO_VIC(1),
        .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
    ) u_hdmi_tx (
        .I_pixel_clk(video_clk), .I_rst(~pix_rst_n),
        .I_edid_read_trig(edid_read_trig),
        .O_edid_read_valid(edid_read_valid),
        .O_edid_read_data(edid_read_data),
        .I_axis_s_user(axis_s_user), .I_axis_s_valid(axis_s_valid),
        .I_axis_s_last(axis_s_last), .I_axis_s_data(axis_s_data),
        .O_axis_s_ready(),
        .I_audio_valid(audio_sample_valid),
        .I_audio_left_data({audio_sample_left, 8'b0}),
        .I_audio_right_data({audio_sample_right, 8'b0}),
        .I_acr_valid(acr_valid), .I_acr_cts(acr_cts), .I_acr_n(acr_n),
        .O_video_locked(hdmi_video_locked),
        .O_ddc_scl(HDMI_DDC_SCL), .IO_ddc_sda(HDMI_DDC_SDA),
        .O_ch0_tmds_data(tmds_ch0_data),
        .O_ch1_tmds_data(tmds_ch1_data),
        .O_ch2_tmds_data(tmds_ch2_data),
        .O_clk_tmds_data(tmds_clk_data)
    );

    hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy (
        .I_pixel_clk(video_clk), .I_serial_clk(pixel_clk_5x),
        .I_rst(~pix_rst_n | ~pix_5x_rst_n),
        .I_tmds_channel_0(tmds_ch0_data),
        .I_tmds_channel_1(tmds_ch1_data),
        .I_tmds_channel_2(tmds_ch2_data),
        .I_tmds_channel_clk(tmds_clk_data),
        .O_tmds_ch0_p(HDMI_D0_P), .O_tmds_ch1_p(HDMI_D1_P),
        .O_tmds_ch2_p(HDMI_D2_P), .O_tmds_clk_p(HDMI_CLK_P)
    );

endmodule
