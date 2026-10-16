`timescale 1ns/1ps
`default_nettype none
// Explicitly selected test source for the captain/A. Never merge with live input.
// 400 frames repeat at 1ms default. Output is control data, NOT ADSR/audio.
module fake_four_key_controls #(
    parameter integer FRAME_CYCLES = 50000
)(
    input wire clk, rst_n,
    output reg [7:0] gate,
    output reg [127:0] key_gain,
    output reg controls_valid,
    output reg [8:0] scenario_frame
);
    reg [31:0] count;
    reg [8:0] cursor;
    reg [7:0] next_gate;
    reg [127:0] next_gain;
    integer i;
    always @* begin
        next_gate = 0; next_gain = 0;
        if (cursor >= 10 && cursor < 30) next_gate = 8'h01;
        else if (cursor >= 30 && cursor < 50) next_gate = 8'h03;
        else if (cursor >= 50 && cursor < 130) next_gate = 8'h0f;
        else if (cursor >= 130 && cursor < 150) next_gate = 8'h0d;
        else if (cursor >= 150 && cursor < 200) next_gate = 8'h0f;
        else if (cursor >= 200 && cursor < 210)
            next_gate = cursor[0] ? 8'h0f : 8'h0e;
        for (i=0; i<4; i=i+1)
            if (next_gate[i]) next_gain[16*i+:16] = 16'd32768;
        if (cursor >= 170 && cursor < 185) next_gain[47:32] = 16'd49152;
        if (cursor >= 185 && cursor < 200) next_gain[47:32] = 16'd16384;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0; cursor <= 0; scenario_frame <= 0;
            gate <= 0; key_gain <= 0; controls_valid <= 0;
        end else begin
            controls_valid <= 0;
            if (count == FRAME_CYCLES-1) begin
                count <= 0;
                gate <= next_gate; key_gain <= next_gain;
                controls_valid <= 1;
                scenario_frame <= cursor;
                cursor <= (cursor == 399) ? 9'd0 : cursor + 9'd1;
            end else count <= count + 32'd1;
        end
    end
// synthesis translate_off
`ifndef SYNTHESIS
    initial if (FRAME_CYCLES < 2) $fatal(1,"FRAME_CYCLES must be >=2");
`endif
// synthesis translate_on
endmodule
`default_nettype wire
