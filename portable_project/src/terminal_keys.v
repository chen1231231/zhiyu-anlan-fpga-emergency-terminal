module terminal_keys #(parameter integer CLOCK_HZ=25000000)(
    input wire clk,rst_n,key_n,
    output reg short_press,long_press,
    output wire pressed_level
);
    wire pressed, level;
    button_event #(.CLK_HZ(CLOCK_HZ),.DEBOUNCE_MS(20)) u_key(
        .clk(clk),.rst_n(rst_n),.key_n(key_n),.press(pressed),.level(level));
    assign pressed_level=level;
    reg prev,held;
    reg [25:0] ticks;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin prev<=0; held<=0; ticks<=0; short_press<=0; long_press<=0; end
        else begin
            prev<=level; short_press<=0; long_press<=0;
            if(!level) begin
                ticks<=0; held<=0;
                if(prev && !held) short_press<=1;
            end else if(!held) begin
                if(ticks==CLOCK_HZ-1) begin held<=1; long_press<=1; end
                else ticks<=ticks+1'b1;
            end
        end
    end
endmodule

// A chord is recognized only after both independently debounced keys are down.
// All individual short/long actions stay suppressed until both keys are released.
module terminal_key_chord #(parameter integer CLOCK_HZ=25000000)(
    input wire clk,rst_n,key_a_level,key_b_level,
    output reg chord_press,
    output wire suppress_individual
);
    reg [2:0] state;
    reg [$clog2(CLOCK_HZ+1)-1:0] ticks;
    // Join within 200 ms; total gesture must be shorter than one second.
    // Two drain cycles cover the registered release pulse from terminal_keys.
    assign suppress_individual=state>=2 || (key_a_level && key_b_level);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=0;ticks<=0;chord_press<=0;end
        else begin
            chord_press<=0;
            if((state==1 || state==2) && ticks<CLOCK_HZ-1) ticks<=ticks+1'b1;
            case(state)
                0: begin
                    ticks<=0;
                    if(key_a_level && key_b_level) state<=2;
                    else if(key_a_level || key_b_level) state<=1;
                end
                1: if(key_a_level && key_b_level) state<=ticks<CLOCK_HZ/5 ? 2:3;
                   else if(!key_a_level && !key_b_level) state<=0;
                2: if(!key_a_level || !key_b_level) begin
                    chord_press<=ticks<CLOCK_HZ-1;state<=3;
                end
                3: if(!key_a_level && !key_b_level) state<=4;
                4: state<=5;
                5: state<=0;
                default:state<=0;
            endcase
        end
    end
endmodule
