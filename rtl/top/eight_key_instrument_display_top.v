`timescale 1ns/1ps
`default_nettype none
// Real B eight-channel input with the captain's 20-partial piano engine.
// Board pin assignments and the shared reset stay in this integration top.
module eight_key_instrument_display_top #(
    parameter ROM_FILE = "tables/sine_1024_16bit.hex",
    parameter [95:0] TON_PACK = {8{12'd256}},
    parameter [95:0] TOFF_PACK = {8{12'd128}},
    parameter [95:0] RAW_MIN_PACK = {8{12'd128}},
    parameter [95:0] RAW_MAX_PACK = {8{12'd3840}},
    // Retain A's board-tested four-key gain floor; B's own default is 4096.
    // This remains a development override, NOT eight measured calibrations.
    parameter [127:0] MIN_GAIN_PACK = {8{16'd32768}},
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer LCD_SPI_HALF_CYCLES = 5,
    parameter integer LCD_RESET_LOW_CYCLES = 5000000,
    parameter integer LCD_RESET_HIGH_CYCLES = 2500000,
    parameter integer LCD_SLEEP_OUT_CYCLES = 6000000,
    parameter integer LCD_PAGE_HOLD_CYCLES = 500000,
    parameter integer ATTACK_SAMPLES = 98,
    parameter integer DECAY_SAMPLES = 195312,
    parameter integer RELEASE_SAMPLES = 7324,
    parameter [15:0] SUSTAIN_LEVEL = 16'd0,
    parameter integer GUITAR_ATTACK_SAMPLES=49,
    parameter integer GUITAR_DECAY_SAMPLES=146484,
    parameter integer GUITAR_RELEASE_SAMPLES=2441,
    parameter [15:0] GUITAR_SUSTAIN_LEVEL=16'd0,
    parameter integer GUITAR_CONTINUOUS_PRESSURE=0,
    parameter [15:0] GUITAR_LOOP_GAIN=16'd65500,
    parameter integer BT_CLKS_PER_BIT=5208,
    parameter integer TEACH_TICK_CYCLES=50000,
    parameter integer TEACH_FRAME_TIMEOUT_MS=10,
    parameter integer VIBRATO_DEPTH_SAMPLES=16,
    parameter [31:0] VIBRATO_PHASE_STEP=32'd439805,
    parameter integer VIBRATO_RAMP_BITS=8
)(
    input wire clk,rst_n,adc_miso,key1_n,key2_n,bt_rx,
    output wire bt_tx,
    output wire [7:0] led,
    output wire adc_cs_n,adc_sclk,adc_mosi,bclk,ws,din,
    output wire lcd_sck,lcd_sda,lcd_cs_n,lcd_rs,lcd_res_n
);
    wire run_rst_n;
    wire [2:0] button_events;
    wire [1:0] key_held,octave_select;
    wire timbre_select,settings_pending;
    wire [7:0] gate;
    wire [127:0] key_gain;
    wire [7:0] pressure_gate;
    wire [127:0] pressure_gain;
    wire pressure_valid;
    wire teach_active,teach_done,teach_fault,teach_stale;
    wire loading,song_valid,tx_overflow;
    wire [8:0] song_count;
    wire [7:0] lesson_step,target_mask;
    wire [2:0] teach_state;
    wire [255:0] phase_steps;
    wire controls_valid,frame_valid,scan_start,scan_busy,timeout;
    wire [95:0] raw_frame,control_raw_frame;
    wire [31:0] timeout_count,underrun_count,discarded_count;
    wire sample_ce,mixed_valid,frame_tick,alignment_error;
    wire signed [15:0] mixed_sample,synth_sample;
    wire synth_valid,vibrato_enable,vibrato_overrun;
    wire [127:0] envelopes,held_gains;
    wire [23:0] states;
    reset_sync reset_release(.clk(clk),.rst_n(rst_n),.run_rst_n(run_rst_n));
    // Captain table: CH0 low, C4 D4 E4 F4 G4 A4 B4 C5.
    note_steps pitch_table (.phase_steps(phase_steps));
    pressure_eight_keys_input #(
        .TON_PACK(TON_PACK),.TOFF_PACK(TOFF_PACK),
        .RAW_MIN_PACK(RAW_MIN_PACK),.RAW_MAX_PACK(RAW_MAX_PACK),
        .MIN_GAIN_PACK(MIN_GAIN_PACK)
    ) pressure (
        .clk(clk),.rst_n(run_rst_n),.miso(adc_miso),
        .cs_n(adc_cs_n),.sclk(adc_sclk),.mosi(adc_mosi),
        .gate(pressure_gate),.key_gain(pressure_gain),.controls_valid(pressure_valid),
        .raw_frame(raw_frame),.frame_valid(frame_valid),
        .scan_start(scan_start),.scan_busy(scan_busy),.timeout(timeout),
        .timeout_count(timeout_count),.control_raw_frame(control_raw_frame)
    );
    // Bluetooth tutorial is an observer: no automatic audio/control source.
    assign gate=pressure_gate;
    assign key_gain=pressure_gain;
    assign controls_valid=pressure_valid;
    bluetooth_teach_control #(
        .CLKS_PER_BIT(BT_CLKS_PER_BIT),.TICK_CYCLES(TEACH_TICK_CYCLES),
        .FRAME_TIMEOUT_MS(TEACH_FRAME_TIMEOUT_MS)
    ) bluetooth (
        .clk(clk),.rst_n(run_rst_n),.bt_rx(bt_rx),.bt_tx(bt_tx),
        .controls_valid(pressure_valid),.gate(pressure_gate),.led(led),
        .active(teach_active),.done(teach_done),.fault(teach_fault),.input_stale(teach_stale),
        .loading(loading),.song_valid(song_valid),.song_count(song_count),
        .lesson_step(lesson_step),.target_mask(target_mask),.state(teach_state),
        .vibrato_enable(vibrato_enable),.tx_overflow(tx_overflow)
    );
    function_keys_input #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) function_keys(
        .clk(clk),.rst_n(run_rst_n),.key1_n(key1_n),.key2_n(key2_n),
        .button_events(button_events),.key_held(key_held));
    // E0 request, E83 active voices, E84 mix. Audio requests are 1024 clocks apart.
    // The mixer applies /8 once. No extra output shift is added here.
    dual_timbre_core #(
        .ROM_FILE(ROM_FILE),.ATTACK_SAMPLES(ATTACK_SAMPLES),
        .DECAY_SAMPLES(DECAY_SAMPLES),.RELEASE_SAMPLES(RELEASE_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
        .GUITAR_ATTACK_SAMPLES(GUITAR_ATTACK_SAMPLES),
        .GUITAR_DECAY_SAMPLES(GUITAR_DECAY_SAMPLES),
        .GUITAR_RELEASE_SAMPLES(GUITAR_RELEASE_SAMPLES),
        .GUITAR_SUSTAIN_LEVEL(GUITAR_SUSTAIN_LEVEL),
        .GUITAR_CONTINUOUS_PRESSURE(GUITAR_CONTINUOUS_PRESSURE),
        .GUITAR_LOOP_GAIN(GUITAR_LOOP_GAIN)
    ) engine_core (
        .clk(clk),.rst_n(run_rst_n),.sample_ce(sample_ce),
        .gate(gate),.key_gain(key_gain),.phase_steps(phase_steps),
        .controls_valid(controls_valid),.button_events(button_events),.mixed_sample(synth_sample),
        .mixed_valid(synth_valid),.alignment_error(alignment_error),
        .voice_samples(),.voice_valid(),.envelopes(envelopes),
        .states(states),.held_gains(held_gains),
        .timbre_select(timbre_select),.octave_select(octave_select),.settings_pending(settings_pending)
    );
    audio_vibrato #(
        .DEPTH_SAMPLES(VIBRATO_DEPTH_SAMPLES),.LFO_PHASE_STEP(VIBRATO_PHASE_STEP),
        .RAMP_BITS(VIBRATO_RAMP_BITS)
    ) vibrato (
        .clk(clk),.rst_n(run_rst_n),.enable(vibrato_enable),
        .in_sample(synth_sample),.in_valid(synth_valid),
        .out_sample(mixed_sample),.out_valid(mixed_valid),.overrun(vibrato_overrun)
    );
    audio_output audio (
        .clk(clk),.rst_n(run_rst_n),.mixed_data(mixed_sample),
        .mixed_valid(mixed_valid),.sample_ce(sample_ce),
        .bclk(bclk),.ws(ws),.din(din),.frame_tick(frame_tick),
        .underrun_count(underrun_count),.discarded_count(discarded_count)
    );
    piano_spectrum_display #(
        .SPI_HALF_CYCLES(LCD_SPI_HALF_CYCLES),
        .RESET_LOW_CYCLES(LCD_RESET_LOW_CYCLES),
        .RESET_HIGH_CYCLES(LCD_RESET_HIGH_CYCLES),
        .SLEEP_OUT_CYCLES(LCD_SLEEP_OUT_CYCLES),
        .PAGE_HOLD_CYCLES(LCD_PAGE_HOLD_CYCLES)
    ) display (
        .clk(clk),.rst_n(run_rst_n),.gate(gate),
        .controls_valid(controls_valid),.octave_select(octave_select),
        .timbre_select(timbre_select),
        .mixed_sample(mixed_sample),.mixed_valid(mixed_valid),
        .spectrum_overrun(),
        .lcd_sck(lcd_sck),.lcd_sda(lcd_sda),.lcd_cs_n(lcd_cs_n),
        .lcd_rs(lcd_rs),.lcd_res_n(lcd_res_n)
    );
endmodule
`default_nettype wire
