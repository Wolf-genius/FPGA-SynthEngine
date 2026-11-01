`timescale 1ns/1ps
`default_nettype none
module dual_timbre_core #(
    parameter ROM_FILE = "tables/sine_1024_16bit.hex",
    parameter integer ATTACK_SAMPLES = 98,
    parameter integer DECAY_SAMPLES = 195312,
    parameter integer RELEASE_SAMPLES = 7324,
    parameter [15:0] SUSTAIN_LEVEL = 16'd0,
    parameter integer GUITAR_ATTACK_SAMPLES=49,
    parameter integer GUITAR_DECAY_SAMPLES=146484,
    parameter integer GUITAR_RELEASE_SAMPLES=2441,
    parameter [15:0] GUITAR_SUSTAIN_LEVEL=16'd0,
    parameter integer GUITAR_CONTINUOUS_PRESSURE=0,
    parameter [15:0] GUITAR_LOOP_GAIN=16'd65500
)(
    input wire clk, rst_n, sample_ce,
    // One atomic control frame. The eight keys are fixed to eight independent voices.
    input wire [7:0] gate,
    input wire [127:0] key_gain,
    input wire [255:0] phase_steps,
    input wire controls_valid,
    input wire [2:0] button_events,
    output reg signed [15:0] mixed_sample,
    output reg mixed_valid,
    output reg alignment_error,
    output wire [127:0] voice_samples,
    output wire [7:0] voice_valid,
    output wire [127:0] envelopes,
    output wire [23:0] states,
    output wire [127:0] held_gains,
    output wire timbre_select,
    output wire [1:0] octave_select,
    output wire settings_pending
);
    reg [7:0] gate_saved;
    reg [127:0] gain_saved;
    reg [255:0] steps_saved;
    // E0 request -> E83 piano output -> E84 registered mix (1.68 us at 50MHz).
    // Requests must be >=84 clocks apart; the audio engine uses 1024 clocks.
    // This deterministic schedule establishes the sample group without FIFOs.
    reg [83:0] request_pipe;
    wire signed [18:0] sum19;
    wire signed [15:0] mix_now;
    wire group_ok = (voice_valid == {8{request_pipe[83]}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_saved <= 0;
            gain_saved <= 0;
            steps_saved <= 0;
        end else if (controls_valid) begin
            gate_saved <= gate;
            gain_saved <= key_gain;
            steps_saved <= phase_steps;
        end
    end

    wire safe_to_apply=(request_pipe==0) && !sample_ce &&
        (gate_saved==0) && (gate==0) && (states==0) && !controls_valid;
    instrument_settings settings(
        .clk(clk),.rst_n(rst_n),.safe_to_apply(safe_to_apply),
        .button_events(button_events),.timbre_select(timbre_select),
        .octave_select(octave_select),.settings_pending(settings_pending));
    wire [255:0] effective_steps;
    genvar k;
    generate for (k=0; k<8; k=k+1) begin : voices
        assign effective_steps[k*32+:32]=(octave_select==1) ?
            steps_saved[k*32+:32]<<1 : (octave_select==2) ?
            steps_saved[k*32+:32]>>1 : steps_saved[k*32+:32];
        dual_timbre_voice #(
            .VOICE_INDEX(k), .ATTACK_SAMPLES(ATTACK_SAMPLES),
            .DECAY_SAMPLES(DECAY_SAMPLES), .RELEASE_SAMPLES(RELEASE_SAMPLES),
            .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
            .GUITAR_ATTACK_SAMPLES(GUITAR_ATTACK_SAMPLES),
            .GUITAR_DECAY_SAMPLES(GUITAR_DECAY_SAMPLES),
            .GUITAR_RELEASE_SAMPLES(GUITAR_RELEASE_SAMPLES),
            .GUITAR_SUSTAIN_LEVEL(GUITAR_SUSTAIN_LEVEL),
            .GUITAR_CONTINUOUS_PRESSURE(GUITAR_CONTINUOUS_PRESSURE),
            .GUITAR_LOOP_GAIN(GUITAR_LOOP_GAIN)
        ) u_voice (
            .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
            .phase_step(effective_steps[k*32 +: 32]),.timbre_select(timbre_select),
            .gate(gate_saved[k]), .gain(gain_saved[k*16 +: 16]),
            .sample(voice_samples[k*16 +: 16]), .sample_valid(voice_valid[k]),
            .envelope_dbg(envelopes[k*16 +: 16]),
            .state_dbg(states[k*3 +: 3]),
            .held_gain_dbg(held_gains[k*16 +: 16])
        );
    end endgenerate

    // Each voice contains its own initialized ROM and read address.
    // No assumption of eight reads from a single-port ROM is made.
    mixer8 mixer (
        .samples(voice_samples), .sum19(sum19), .mixed_sample(mix_now)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_pipe <= 0;
            mixed_sample <= 0;
            mixed_valid <= 0;
            alignment_error <= 0;
        end else begin
            request_pipe <= {request_pipe[82:0], sample_ce};
            mixed_valid <= 0;
            if (!group_ok || (sample_ce && (|request_pipe[82:0]))) begin
                // Drop the mismatched group; sticky fault requires reset.
                alignment_error <= 1;
                mixed_sample <= 0;
            end else if (request_pipe[83] && !alignment_error) begin
                mixed_sample <= mix_now;
                mixed_valid <= 1;
            end
        end
    end
endmodule
`default_nettype wire
