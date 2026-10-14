`timescale 1ns/1ps
`default_nettype none
// Explicit TEST source: silent -> light -> heavy -> released, repeat.
// Never instantiate simultaneously with the real source on the same bus.
module fake_ch0_controls #(
    parameter integer FRAME_CYCLES=50000, STAGE_FRAMES=1000
)(
    input wire clk, rst_n,
    output reg [7:0] gate,
    output reg [127:0] key_gain,
    output reg controls_valid
);
    localparam integer CW=(FRAME_CYCLES<2)?1:$clog2(FRAME_CYCLES);
    localparam integer FW=(STAGE_FRAMES<2)?1:$clog2(STAGE_FRAMES);
    reg [CW-1:0] count;
    reg [FW-1:0] frame_count;
    reg [1:0] stage;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            count<=0; frame_count<=0; stage<=0;
            gate<=0; key_gain<=0; controls_valid<=0;
        end else begin
            controls_valid<=0;
            if(count==FRAME_CYCLES-1) begin
                count<=0; controls_valid<=1;
                case(stage)
                    1: begin gate<=8'h01; key_gain<={112'd0,16'h4000}; end
                    2: begin gate<=8'h01; key_gain<={112'd0,16'hc000}; end
                    default: begin gate<=0; key_gain<=0; end
                endcase
                if(frame_count==STAGE_FRAMES-1) begin
                    frame_count<=0; stage<=stage+2'd1;
                end else frame_count<=frame_count+1'b1;
            end else count<=count+1'b1;
        end
    end
`ifndef SYNTHESIS
    initial if(FRAME_CYCLES<2 || STAGE_FRAMES<1) $fatal(1,"Invalid test timing");
`endif
endmodule
`default_nettype wire
