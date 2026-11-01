`timescale 1ns/1ps
`default_nettype none
// B's eight-key delivery entry. Same ports and timing as pressure_keys_input,
// with all eight lanes enabled explicitly. Not a board top; A owns pin/reset
// release constraints. Defaults are development values, NOT measured calibration.
module pressure_eight_keys_input #(
    parameter [95:0] TON_PACK = {8{12'd256}},
    parameter [95:0] TOFF_PACK = {8{12'd128}},
    parameter [95:0] RAW_MIN_PACK = {8{12'd128}},
    parameter [95:0] RAW_MAX_PACK = {8{12'd3840}},
    parameter [127:0] MIN_GAIN_PACK = {8{16'd4096}}
)(
    input wire clk, rst_n, miso,
    output wire cs_n, sclk, mosi,
    output wire [7:0] gate,
    output wire [127:0] key_gain,
    output wire controls_valid,
    output wire [95:0] raw_frame,
    output wire frame_valid, scan_start, scan_busy, timeout,
    output wire [31:0] timeout_count,
    output wire [95:0] control_raw_frame
);
    pressure_keys_input #(
        .ACTIVE_KEYS(8), .TON_PACK(TON_PACK), .TOFF_PACK(TOFF_PACK),
        .RAW_MIN_PACK(RAW_MIN_PACK), .RAW_MAX_PACK(RAW_MAX_PACK),
        .MIN_GAIN_PACK(MIN_GAIN_PACK)
    ) input_chain (
        .clk(clk), .rst_n(rst_n), .miso(miso),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi),
        .gate(gate), .key_gain(key_gain), .controls_valid(controls_valid),
        .raw_frame(raw_frame), .frame_valid(frame_valid),
        .scan_start(scan_start), .scan_busy(scan_busy),
        .timeout(timeout), .timeout_count(timeout_count),
        .control_raw_frame(control_raw_frame)
    );
endmodule
`default_nettype wire
