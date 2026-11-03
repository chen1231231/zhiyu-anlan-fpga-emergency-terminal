`timescale 1ns/1ps

// Bounded FAT32 streamer for compact PCM files. A new 512-byte sector is
// requested only when the downstream FIFO reserves a complete sector.
module fat32_audio_streamer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        file_start,
    input  wire        file_stop,
    input  wire        sector_admit,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    output wire        file_busy,
    output reg         file_done,
    output reg         file_valid,
    output reg  [7:0]  file_byte,
    output reg  [7:0]  fs_error,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);
    localparam ST_IDLE=3'd0, ST_DATA_REQ=3'd1, ST_DATA_WAIT=3'd2;
    localparam ST_FAT_REQ=3'd3, ST_FAT_WAIT=3'd4, ST_FAT_PARSE=3'd5,
               ST_FINISH=3'd6;
    localparam ERR_SECTOR=8'h10, ERR_CLUSTER=8'h24, ERR_EARLY_EOF=8'h25;

    reg [2:0] state;
    reg [31:0] current_cluster;
    reg [31:0] remaining_bytes;
    reg [7:0] sector_in_cluster;
    reg [8:0] fat_entry_offset;
    reg [7:0] fat_byte0, fat_byte1, fat_byte2, fat_byte3;
    wire [31:0] parsed_next = {4'd0,fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0};

    assign file_busy = state != ST_IDLE;

    task fail;
        input [7:0] code;
        begin fs_error <= code; state <= ST_FINISH; end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            current_cluster <= 0;
            remaining_bytes <= 0;
            sector_in_cluster <= 0;
            fat_entry_offset <= 0;
            fat_byte0 <= 0; fat_byte1 <= 0; fat_byte2 <= 0; fat_byte3 <= 0;
            file_done <= 0; file_valid <= 0; file_byte <= 0;
            fs_error <= 0; sector_req <= 0; sector_lba <= 0;
        end else begin
            file_done <= 0;
            file_valid <= 0;
            sector_req <= 0;

            if (file_stop) begin
                state <= ST_IDLE;
                remaining_bytes <= 0;
                fs_error <= 0;
            end else begin
                if (state == ST_DATA_WAIT && sector_valid && remaining_bytes != 0) begin
                    file_valid <= 1'b1;
                    file_byte <= sector_byte;
                    remaining_bytes <= remaining_bytes - 1'b1;
                end
                if (state == ST_FAT_WAIT && sector_valid) begin
                    if (sector_byte_index == fat_entry_offset) fat_byte0 <= sector_byte;
                    else if (sector_byte_index == fat_entry_offset + 1'b1) fat_byte1 <= sector_byte;
                    else if (sector_byte_index == fat_entry_offset + 2'd2) fat_byte2 <= sector_byte;
                    else if (sector_byte_index == fat_entry_offset + 2'd3) fat_byte3 <= sector_byte;
                end

                case (state)
                    ST_IDLE: if (file_start) begin
                        fs_error <= 0;
                        current_cluster <= first_cluster;
                        remaining_bytes <= file_size;
                        sector_in_cluster <= 0;
                        if (file_size == 0) state <= ST_FINISH;
                        else if (first_cluster < 2 || first_cluster > max_cluster ||
                                 sectors_per_cluster == 0) fail(ERR_CLUSTER);
                        else begin
                            sector_lba <= data_start_lba +
                                          (first_cluster - 2) * sectors_per_cluster;
                            state <= ST_DATA_REQ;
                        end
                    end
                    ST_DATA_REQ: if (sector_admit && !sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_DATA_WAIT;
                    end
                    ST_DATA_WAIT: if (sector_done) begin
                        if (sector_error != 0) fail(ERR_SECTOR);
                        else if (remaining_bytes == 0 ||
                                 (remaining_bytes == 1 && sector_valid)) state <= ST_FINISH;
                        else if (sector_in_cluster + 1'b1 < sectors_per_cluster) begin
                            sector_in_cluster <= sector_in_cluster + 1'b1;
                            sector_lba <= sector_lba + 1'b1;
                            state <= ST_DATA_REQ;
                        end else begin
                            sector_in_cluster <= 0;
                            fat_entry_offset <= {current_cluster[6:0],2'b00};
                            sector_lba <= fat_start_lba + (current_cluster >> 7);
                            state <= ST_FAT_REQ;
                        end
                    end
                    ST_FAT_REQ: if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_FAT_WAIT;
                    end
                    ST_FAT_WAIT: if (sector_done) begin
                        if (sector_error != 0) fail(ERR_SECTOR);
                        else state <= ST_FAT_PARSE;
                    end
                    ST_FAT_PARSE: begin
                        if (parsed_next >= 32'h0ffffff8) fail(ERR_EARLY_EOF);
                        else if (parsed_next < 2 || parsed_next > max_cluster ||
                                 parsed_next == current_cluster) fail(ERR_CLUSTER);
                        else begin
                            current_cluster <= parsed_next;
                            sector_lba <= data_start_lba +
                                          (parsed_next - 2) * sectors_per_cluster;
                            state <= ST_DATA_REQ;
                        end
                    end
                    ST_FINISH: begin
                        file_done <= 1'b1;
                        state <= ST_IDLE;
                    end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
