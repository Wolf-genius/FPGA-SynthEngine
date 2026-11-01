`timescale 1ns/1ps
`default_nettype none
// Receive all one-clock events. Apply the accumulated settings together only
// when the core reports no held keys, no release tail, and no in-flight sample.
module instrument_settings(
    input wire clk,rst_n,safe_to_apply,
    input wire [2:0] button_events,
    output reg timbre_select,
    output reg [1:0] octave_select,
    output wire settings_pending
);
    reg wanted_timbre;
    reg [1:0] wanted_octave;
    wire next_timbre=wanted_timbre ^ button_events[0];
    wire [1:0] next_octave=button_events[1] ?
        (wanted_octave==2 ? 2'd0:wanted_octave+1'b1):wanted_octave;
    assign settings_pending=(wanted_timbre!=timbre_select || wanted_octave!=octave_select);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wanted_timbre<=0;wanted_octave<=0;timbre_select<=0;octave_select<=0;
        end else begin
            wanted_timbre<=next_timbre;wanted_octave<=next_octave;
            if(safe_to_apply) begin
                timbre_select<=next_timbre;octave_select<=next_octave;
            end
        end
    end
endmodule
`default_nettype wire
