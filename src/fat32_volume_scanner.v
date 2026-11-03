`timescale 1ns/1ps

module fat32_volume_scanner (
    input wire clk, input wire rst_n, input wire scan_start,
    output wire scan_busy, output reg scan_done, output reg [7:0] fs_error,
    output reg [31:0] partition_lba, output reg [7:0] sectors_per_cluster,
    output reg [31:0] fat_start_lba, data_start_lba, max_cluster,
    output reg [5:0] resource_valid,
    output reg [31:0] resource0_cluster, resource1_cluster, resource2_cluster,
    output reg [31:0] resource3_cluster, resource4_cluster, resource5_cluster,
    output reg [31:0] resource0_size, resource1_size, resource2_size,
    output reg [31:0] resource3_size, resource4_size, resource5_size,
    output reg [3:0] audio_resource_valid,
    output reg [31:0] audio0_cluster, audio1_cluster, audio2_cluster, audio3_cluster,
    output reg [31:0] audio0_size, audio1_size, audio2_size, audio3_size,
    output reg plan_resource_valid, output reg [31:0] plan_cluster, plan_size,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire sector_busy, input wire sector_valid, input wire [7:0] sector_byte,
    input wire [8:0] sector_byte_index, input wire sector_done,
    input wire [7:0] sector_error
);
    localparam ERR_NONE=8'h00, ERR_SECTOR=8'h10, ERR_BOOT_SIGNATURE=8'h20;
    localparam ERR_UNSUPPORTED_BPB=8'h21, ERR_RESOURCE_MISSING=8'h22;
    localparam ST_IDLE=4'd0, ST_READ0_REQ=4'd1, ST_READ0_WAIT=4'd2;
    localparam ST_BOOT_PARSE=4'd3, ST_BOOT_REQ=4'd4, ST_BOOT_WAIT=4'd5;
    localparam ST_ROOT_REQ=4'd6, ST_ROOT_WAIT=4'd7, ST_FINISH=4'd9;
    localparam ST_BOOT_LAYOUT=4'd10, ST_BOOT_ROOT=4'd11;
    localparam ST_ROOT_FAT_REQ=4'd12, ST_ROOT_FAT_WAIT=4'd13, ST_ROOT_FAT_PARSE=4'd14;

    reg [3:0] state;
    reg [31:0] root_hops, root_cluster, total_sectors, fat_sectors;
    reg [7:0] fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] root_lba, data_sector_count, fat_span;
    reg [2:0] sectors_per_cluster_shift;
    reg [6:0] root_sector_index;

    // Retain only fields used by the scanner. This avoids implementing a
    // 512-byte sector buffer as flip-flops plus large asynchronous muxes.
    reg [7:0] boot_jump, mbr_partition_type;
    reg [15:0] boot_signature, bpb_bytes_per_sector, bpb_reserved_sectors;
    reg [15:0] bpb_root_entries, bpb_fat16_sectors;
    reg [7:0] bpb_sectors_per_cluster, bpb_fat_count;
    reg [31:0] mbr_partition_lba, bpb_total_sectors;
    reg [31:0] bpb_fat32_sectors, bpb_root_cluster;

    // Assemble one directory entry while its 32 bytes stream in.
    reg [87:0] entry_name;
    reg [7:0] entry_attr, entry_first;
    reg [15:0] entry_cluster_high, entry_cluster_low;
    reg [23:0] entry_size_low;
    reg directory_end_seen;
    reg [31:0] root_next;

    assign scan_busy=(state!=ST_IDLE);

    function valid_spc;
        input [7:0] value;
        begin valid_spc=value!=0 && ((value&(value-1'b1))==0); end
    endfunction
    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case(value)
                8'd2:spc_shift=1; 8'd4:spc_shift=2; 8'd8:spc_shift=3;
                8'd16:spc_shift=4; 8'd32:spc_shift=5; 8'd64:spc_shift=6;
                8'd128:spc_shift=7; default:spc_shift=0;
            endcase
        end
    endfunction
    function [7:0] sector_error_detail;
        input [7:0] value;
        begin
            case(value)
                8'h01:sector_error_detail=8'h11; 8'h02:sector_error_detail=8'h12;
                8'h03:sector_error_detail=8'h13; 8'h04:sector_error_detail=8'h14;
                8'h05:sector_error_detail=8'h15; 8'h06:sector_error_detail=8'h16;
                8'he1:sector_error_detail=8'h1e; default:sector_error_detail=ERR_SECTOR;
            endcase
        end
    endfunction
    task finish_with_error;
        input [7:0] code;
        begin fs_error<=code; state<=ST_FINISH; end
    endtask
    task accept_directory_entry;
        input [87:0] short_name;
        input [7:0] attributes;
        input [31:0] first_cluster;
        input [31:0] file_size;
        begin
            if(entry_first!=8'h00 && entry_first!=8'he5 &&
               attributes!=8'h0f && (attributes&8'h18)==0) begin
                case(short_name)
                    88'h4e4f524d414c2020424d50:begin resource0_cluster<=first_cluster;resource0_size<=file_size;resource_valid[0]<=1;end
                    88'h5341464554592020424d50:begin resource1_cluster<=first_cluster;resource1_size<=file_size;resource_valid[1]<=1;end
                    88'h4649524520202020424d50:begin resource2_cluster<=first_cluster;resource2_size<=file_size;resource_valid[2]<=1;end
                    88'h5155414b45202020424d50:begin resource3_cluster<=first_cluster;resource3_size<=file_size;resource_valid[3]<=1;end
                    88'h464c4f4f44202020424d50:begin resource4_cluster<=first_cluster;resource4_size<=file_size;resource_valid[4]<=1;end
                    88'h4556414320202020424d50:begin resource5_cluster<=first_cluster;resource5_size<=file_size;resource_valid[5]<=1;end
                    88'h414c41524d20202050434d:begin audio0_cluster<=first_cluster;audio0_size<=file_size;audio_resource_valid[0]<=1;end
                    88'h464952452020202050434d:begin audio1_cluster<=first_cluster;audio1_size<=file_size;audio_resource_valid[1]<=1;end
                    88'h5155414b4520202050434d:begin audio2_cluster<=first_cluster;audio2_size<=file_size;audio_resource_valid[2]<=1;end
                    88'h464c4f4f4420202050434d:begin audio3_cluster<=first_cluster;audio3_size<=file_size;audio_resource_valid[3]<=1;end
                    88'h504c414e2020202042494e:begin plan_cluster<=first_cluster;plan_size<=file_size;plan_resource_valid<=1;end
                    default:;
                endcase
            end
        end
    endtask

    // MBR and BPB capture.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            boot_jump<=0;boot_signature<=0;mbr_partition_type<=0;mbr_partition_lba<=0;
            bpb_bytes_per_sector<=0;bpb_sectors_per_cluster<=0;bpb_reserved_sectors<=0;
            bpb_fat_count<=0;bpb_root_entries<=0;bpb_fat16_sectors<=0;
            bpb_total_sectors<=0;bpb_fat32_sectors<=0;bpb_root_cluster<=0;
        end else if(((state==ST_READ0_REQ)||(state==ST_BOOT_REQ))&&!sector_busy) begin
            boot_jump<=0;boot_signature<=0;mbr_partition_type<=0;mbr_partition_lba<=0;
            bpb_bytes_per_sector<=0;bpb_sectors_per_cluster<=0;bpb_reserved_sectors<=0;
            bpb_fat_count<=0;bpb_root_entries<=0;bpb_fat16_sectors<=0;
            bpb_total_sectors<=0;bpb_fat32_sectors<=0;bpb_root_cluster<=0;
        end else if(((state==ST_READ0_WAIT)||(state==ST_BOOT_WAIT))&&sector_valid) begin
            case(sector_byte_index)
                9'd0:boot_jump<=sector_byte;
                9'd11:bpb_bytes_per_sector[7:0]<=sector_byte;
                9'd12:bpb_bytes_per_sector[15:8]<=sector_byte;
                9'd13:bpb_sectors_per_cluster<=sector_byte;
                9'd14:bpb_reserved_sectors[7:0]<=sector_byte;
                9'd15:bpb_reserved_sectors[15:8]<=sector_byte;
                9'd16:bpb_fat_count<=sector_byte;
                9'd17:bpb_root_entries[7:0]<=sector_byte;
                9'd18:bpb_root_entries[15:8]<=sector_byte;
                9'd22:bpb_fat16_sectors[7:0]<=sector_byte;
                9'd23:bpb_fat16_sectors[15:8]<=sector_byte;
                9'd32:bpb_total_sectors[7:0]<=sector_byte;
                9'd33:bpb_total_sectors[15:8]<=sector_byte;
                9'd34:bpb_total_sectors[23:16]<=sector_byte;
                9'd35:bpb_total_sectors[31:24]<=sector_byte;
                9'd36:bpb_fat32_sectors[7:0]<=sector_byte;
                9'd37:bpb_fat32_sectors[15:8]<=sector_byte;
                9'd38:bpb_fat32_sectors[23:16]<=sector_byte;
                9'd39:bpb_fat32_sectors[31:24]<=sector_byte;
                9'd44:bpb_root_cluster[7:0]<=sector_byte;
                9'd45:bpb_root_cluster[15:8]<=sector_byte;
                9'd46:bpb_root_cluster[23:16]<=sector_byte;
                9'd47:bpb_root_cluster[31:24]<=sector_byte;
                9'd450:mbr_partition_type<=sector_byte;
                9'd454:mbr_partition_lba[7:0]<=sector_byte;
                9'd455:mbr_partition_lba[15:8]<=sector_byte;
                9'd456:mbr_partition_lba[23:16]<=sector_byte;
                9'd457:mbr_partition_lba[31:24]<=sector_byte;
                9'd510:boot_signature[7:0]<=sector_byte;
                9'd511:boot_signature[15:8]<=sector_byte;
                default:;
            endcase
        end
    end

    // Directory-entry capture.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            entry_name<=0;entry_attr<=0;entry_first<=0;entry_cluster_high<=0;
            entry_cluster_low<=0;entry_size_low<=0;directory_end_seen<=0;
        end else if(state==ST_ROOT_REQ&&!sector_busy) begin
            entry_name<=0;entry_attr<=0;entry_first<=0;entry_cluster_high<=0;
            entry_cluster_low<=0;entry_size_low<=0;directory_end_seen<=0;
        end else if(state==ST_ROOT_WAIT&&sector_valid) begin
            case(sector_byte_index[4:0])
                5'd0:begin entry_name[87:80]<=sector_byte;entry_first<=sector_byte;
                    if(sector_byte==8'h00)directory_end_seen<=1;end
                5'd1:entry_name[79:72]<=sector_byte; 5'd2:entry_name[71:64]<=sector_byte;
                5'd3:entry_name[63:56]<=sector_byte; 5'd4:entry_name[55:48]<=sector_byte;
                5'd5:entry_name[47:40]<=sector_byte; 5'd6:entry_name[39:32]<=sector_byte;
                5'd7:entry_name[31:24]<=sector_byte; 5'd8:entry_name[23:16]<=sector_byte;
                5'd9:entry_name[15:8]<=sector_byte; 5'd10:entry_name[7:0]<=sector_byte;
                5'd11:entry_attr<=sector_byte;
                5'd20:entry_cluster_high[7:0]<=sector_byte;
                5'd21:entry_cluster_high[15:8]<=sector_byte;
                5'd26:entry_cluster_low[7:0]<=sector_byte;
                5'd27:entry_cluster_low[15:8]<=sector_byte;
                5'd28:entry_size_low[7:0]<=sector_byte;
                5'd29:entry_size_low[15:8]<=sector_byte;
                5'd30:entry_size_low[23:16]<=sector_byte;
                default:;
            endcase
        end
    end

    // Root-directory FAT-chain entry capture.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)root_next<=0;
        else if(state==ST_ROOT_FAT_REQ&&!sector_busy)root_next<=0;
        else if(state==ST_ROOT_FAT_WAIT&&sector_valid&&
                sector_byte_index[8:2]==root_cluster[6:0]) begin
            case(sector_byte_index[1:0])
                0:root_next[7:0]<=sector_byte;1:root_next[15:8]<=sector_byte;
                2:root_next[23:16]<=sector_byte;3:root_next[31:24]<={4'd0,sector_byte[3:0]};
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;scan_done<=0;fs_error<=ERR_NONE;partition_lba<=0;
            sectors_per_cluster<=0;fat_start_lba<=0;data_start_lba<=0;max_cluster<=0;
            resource_valid<=0;audio_resource_valid<=0;plan_resource_valid<=0;
            plan_cluster<=0;plan_size<=0;
            audio0_cluster<=0;audio1_cluster<=0;audio2_cluster<=0;audio3_cluster<=0;
            audio0_size<=0;audio1_size<=0;audio2_size<=0;audio3_size<=0;
            resource0_cluster<=0;resource1_cluster<=0;resource2_cluster<=0;
            resource3_cluster<=0;resource4_cluster<=0;resource5_cluster<=0;
            resource0_size<=0;resource1_size<=0;resource2_size<=0;
            resource3_size<=0;resource4_size<=0;resource5_size<=0;
            sector_req<=0;sector_lba<=0;root_cluster<=0;root_hops<=0;
            total_sectors<=0;fat_sectors<=0;fat_count<=0;reserved_sectors<=0;
            root_lba<=0;data_sector_count<=0;fat_span<=0;
            sectors_per_cluster_shift<=0;root_sector_index<=0;
        end else begin
            scan_done<=0;sector_req<=0;
            case(state)
                ST_IDLE:if(scan_start)begin
                    fs_error<=ERR_NONE;partition_lba<=0;resource_valid<=0;
                    audio_resource_valid<=0;plan_resource_valid<=0;
                    plan_cluster<=0;plan_size<=0;root_hops<=0;state<=ST_READ0_REQ;
                end
                ST_READ0_REQ:if(!sector_busy)begin sector_lba<=0;sector_req<=1;state<=ST_READ0_WAIT;end
                ST_READ0_WAIT:if(sector_done)begin
                    if(sector_error!=0)finish_with_error(sector_error_detail(sector_error));
                    else if(boot_signature!=16'haa55)finish_with_error(ERR_BOOT_SIGNATURE);
                    else if(boot_jump==8'heb||boot_jump==8'he9)begin partition_lba<=0;state<=ST_BOOT_PARSE;end
                    else if(mbr_partition_type==8'h0b||mbr_partition_type==8'h0c)begin
                        partition_lba<=mbr_partition_lba;sector_lba<=mbr_partition_lba;state<=ST_BOOT_REQ;end
                    else finish_with_error(ERR_UNSUPPORTED_BPB);
                end
                ST_BOOT_REQ:if(!sector_busy)begin sector_req<=1;state<=ST_BOOT_WAIT;end
                ST_BOOT_WAIT:if(sector_done)begin
                    if(sector_error!=0)finish_with_error(sector_error_detail(sector_error));
                    else if(boot_signature!=16'haa55)finish_with_error(ERR_BOOT_SIGNATURE);
                    else state<=ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE:begin
                    if(bpb_bytes_per_sector!=512||!valid_spc(bpb_sectors_per_cluster)||
                       bpb_reserved_sectors==0||(bpb_fat_count!=1&&bpb_fat_count!=2)||
                       bpb_root_entries!=0||bpb_fat16_sectors!=0||bpb_total_sectors==0||
                       bpb_fat32_sectors==0||bpb_root_cluster<2)
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin
                        sectors_per_cluster<=bpb_sectors_per_cluster;
                        reserved_sectors<=bpb_reserved_sectors;fat_count<=bpb_fat_count;
                        total_sectors<=bpb_total_sectors;fat_sectors<=bpb_fat32_sectors;
                        root_cluster<=bpb_root_cluster;
                        sectors_per_cluster_shift<=spc_shift(bpb_sectors_per_cluster);
                        fat_span<=bpb_fat_count==2?(bpb_fat32_sectors<<1):bpb_fat32_sectors;
                        fat_start_lba<=partition_lba+bpb_reserved_sectors;state<=ST_BOOT_LAYOUT;
                    end
                end
                ST_BOOT_LAYOUT:begin
                    data_start_lba<=partition_lba+reserved_sectors+fat_span;
                    data_sector_count<=total_sectors-reserved_sectors-fat_span;state<=ST_BOOT_ROOT;
                end
                ST_BOOT_ROOT:begin
                    root_sector_index<=0;max_cluster<=(data_sector_count>>sectors_per_cluster_shift)+1'b1;
                    root_lba<=data_start_lba+((root_cluster-2)<<sectors_per_cluster_shift);
                    sector_lba<=data_start_lba+((root_cluster-2)<<sectors_per_cluster_shift);
                    state<=ST_ROOT_REQ;
                end
                ST_ROOT_REQ:if(!sector_busy)begin sector_req<=1;state<=ST_ROOT_WAIT;end
                ST_ROOT_WAIT:begin
                    if(sector_valid&&sector_byte_index[4:0]==31&&!directory_end_seen)
                        accept_directory_entry(entry_name,entry_attr,
                            {entry_cluster_high,entry_cluster_low},{sector_byte,entry_size_low});
                    if(sector_done)begin
                        if(sector_error!=0)finish_with_error(sector_error_detail(sector_error));
                        else if(resource_valid==6'h3f&&audio_resource_valid==4'hf&&plan_resource_valid)
                            state<=ST_FINISH;
                        else if(directory_end_seen)begin
                            if(resource_valid==6'h3f)state<=ST_FINISH;
                            else finish_with_error(ERR_RESOURCE_MISSING);
                        end else if(({1'b0,root_sector_index}+1'b1)<(8'd1<<sectors_per_cluster_shift))begin
                            root_sector_index<=root_sector_index+1'b1;
                            sector_lba<=root_lba+{25'd0,root_sector_index}+1'b1;state<=ST_ROOT_REQ;
                        end else begin
                            sector_lba<=fat_start_lba+(root_cluster>>7);state<=ST_ROOT_FAT_REQ;
                        end
                    end
                end
                ST_ROOT_FAT_REQ:if(!sector_busy)begin sector_req<=1;state<=ST_ROOT_FAT_WAIT;end
                ST_ROOT_FAT_WAIT:if(sector_done)begin
                    if(sector_error!=0)finish_with_error(sector_error_detail(sector_error));
                    else state<=ST_ROOT_FAT_PARSE;
                end
                ST_ROOT_FAT_PARSE:begin
                    if(resource_valid==6'h3f&&audio_resource_valid==4'hf&&plan_resource_valid)state<=ST_FINISH;
                    else if(root_next>=32'h0ffffff8)finish_with_error(ERR_RESOURCE_MISSING);
                    else if(root_next<2||root_next>max_cluster||root_next==root_cluster||root_hops>=max_cluster)
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin
                        root_cluster<=root_next;root_hops<=root_hops+1'b1;root_sector_index<=0;
                        root_lba<=data_start_lba+((root_next-2)<<sectors_per_cluster_shift);
                        sector_lba<=data_start_lba+((root_next-2)<<sectors_per_cluster_shift);
                        state<=ST_ROOT_REQ;
                    end
                end
                ST_FINISH:begin scan_done<=1;state<=ST_IDLE;end
                default:state<=ST_IDLE;
            endcase
        end
    end
endmodule
