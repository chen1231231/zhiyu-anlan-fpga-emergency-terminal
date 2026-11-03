`timescale 1ns/1ps

module tb_fat32_audio_streamer;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg file_start=0, file_stop=0, sector_admit=0;
    reg [31:0] first_cluster=5, file_size=517;
    reg [7:0] sectors_per_cluster=1;
    reg [31:0] fat_start_lba=20, data_start_lba=1000, max_cluster=100;
    wire file_busy, file_done, file_valid, sector_req;
    wire [7:0] file_byte, fs_error;
    wire [31:0] sector_lba;
    reg sector_busy=0, sector_valid=0, sector_done=0;
    reg [7:0] sector_byte=0, sector_error=0;
    reg [8:0] sector_byte_index=0;

    fat32_audio_streamer dut(.*);

    integer request_count=0, output_count=0, i;
    reg [31:0] requested_lba;

    task send_byte;
        input [8:0] index;
        input [7:0] value;
        begin
            @(negedge clk);
            sector_valid=1; sector_byte_index=index; sector_byte=value;
            @(negedge clk);
            sector_valid=0;
        end
    endtask

    always @(posedge clk) begin
        if (file_valid) begin
            if (output_count < 512 && file_byte !== output_count[7:0])
                $fatal(1,"first cluster mismatch at %0d: %02x",output_count,file_byte);
            if (output_count >= 512 && file_byte !== (8'hA0+output_count-512))
                $fatal(1,"second cluster mismatch at %0d: %02x",output_count,file_byte);
            output_count=output_count+1;
        end
    end

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); file_start=1;
        @(negedge clk); file_start=0;
        repeat(5) @(negedge clk);
        if(sector_req) $fatal(1,"request ignored sector_admit");
        sector_admit=1;

        forever begin
            @(posedge clk);
            if(sector_req) begin
                requested_lba=sector_lba;
                request_count=request_count+1;
                sector_busy=1;
                if(request_count==1) begin
                    if(requested_lba!=1003) $fatal(1,"bad first data LBA %0d",requested_lba);
                    for(i=0;i<512;i=i+1) send_byte(i,i[7:0]);
                end else if(request_count==2) begin
                    if(requested_lba!=20) $fatal(1,"bad FAT LBA %0d",requested_lba);
                    send_byte(20,8'h09); send_byte(21,0); send_byte(22,0); send_byte(23,0);
                end else if(request_count==3) begin
                    if(requested_lba!=1007) $fatal(1,"bad second data LBA %0d",requested_lba);
                    for(i=0;i<5;i=i+1) send_byte(i,8'hA0+i);
                end else $fatal(1,"unexpected request %0d",request_count);
                @(negedge clk); sector_done=1; sector_busy=0;
                @(negedge clk); sector_done=0;
            end
            if(file_done) begin
                if(fs_error!=0) $fatal(1,"stream error %02x",fs_error);
                if(output_count!=517) $fatal(1,"byte count %0d",output_count);
                if(request_count!=3) $fatal(1,"request count %0d",request_count);
                $display("PASS audio FAT32 cross-cluster stream and exact file length");
                $finish;
            end
        end
    end

    initial begin #200000; $fatal(1,"simulation timeout"); end
endmodule
