`timescale 1ns/1ps
`default_nettype none
// Integration EXAMPLE: synth_core should implement this same atomic latch rule.
// Outputs here are snapshots for each sample_ce, not synthesized audio.
module control_frame_receiver (
    input wire clk, rst_n,
    input wire [7:0] gate,
    input wire [127:0] key_gain,
    input wire controls_valid, sample_ce,
    output reg [7:0] sample_gate,
    output reg [127:0] sample_gain
);
    reg [7:0] held_gate;
    reg [127:0] held_gain;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            held_gate <= 0; held_gain <= 0;
            sample_gate <= 0; sample_gain <= 0;
        end else begin
            if (controls_valid) begin
                held_gate <= gate;
                held_gain <= key_gain;
            end
            if (sample_ce) begin
                sample_gate <= held_gate;
                sample_gain <= held_gain;
            end
        end
    end
endmodule
`default_nettype wire
