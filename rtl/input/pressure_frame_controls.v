`timescale 1ns/1ps
`default_nettype none
// Eight-key interface, default first four enabled. Packed calibration: CH0 low.
// All inputs synchronous to clk. At acceptance edge E, sample the ENTIRE frame.
// Publish at E+19 (380 ns at 50 MHz), consumer accepts at E+20.
// One input frame per clock is supported; no busy/ready. Normal cadence is 1ms.
module pressure_frame_controls #(
    parameter integer ACTIVE_KEYS = 4,
    parameter [95:0] TON_PACK = {8{12'd256}},
    parameter [95:0] TOFF_PACK = {8{12'd128}},
    parameter [95:0] RAW_MIN_PACK = {8{12'd128}},
    parameter [95:0] RAW_MAX_PACK = {8{12'd3840}},
    parameter [127:0] MIN_GAIN_PACK = {8{16'd4096}}
)(
    input wire clk, rst_n,
    input wire [95:0] raw_frame,
    input wire frame_valid,
    input wire frame_cancel,
    output wire [7:0] gate,
    output wire [127:0] key_gain,
    output wire controls_valid,
    output reg [95:0] control_raw_frame
);
    wire [7:0] lane_gate, lane_valid;
    wire [127:0] lane_gain;
    reg [95:0] raw_pipe [0:18];
    reg [18:0] raw_valid_pipe;
    // Every enabled lane has the same fixed latency. Concatenation publishes
    // all independently registered lane results on the SAME clock edge.
    assign gate = lane_gate;
    assign key_gain = lane_gain;
    assign controls_valid = lane_valid[0];
    integer k;
    genvar i;
    generate for (i=0; i<8; i=i+1) begin: key_lane
        if (i < ACTIVE_KEYS) begin: enabled
            pressure_key_filter #(
                .TON(TON_PACK[12*i+:12]), .TOFF(TOFF_PACK[12*i+:12]),
                .RAW_MIN(RAW_MIN_PACK[12*i+:12]),
                .RAW_MAX(RAW_MAX_PACK[12*i+:12]),
                .MIN_GAIN(MIN_GAIN_PACK[16*i+:16])
            ) filter (
                .clk(clk), .rst_n(rst_n), .raw_data(raw_frame[12*i+:12]),
                .raw_valid(frame_valid), .frame_cancel(frame_cancel),
                .gate(lane_gate[i]), .key_gain(lane_gain[16*i+:16]),
                .controls_valid(lane_valid[i])
            );
        end else begin: disabled
            assign lane_gate[i] = 1'b0;
            assign lane_gain[16*i+:16] = 16'd0;
            assign lane_valid[i] = 1'b0;
        end
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_raw_frame <= 0; raw_valid_pipe <= 0;
            for (k=0; k<19; k=k+1) raw_pipe[k] <= 0;
        end else if (frame_cancel) begin
            // No publication on a failed scan. Cancel pending samples without
            // losing the last complete outward control frame.
            raw_valid_pipe <= 0;
            for (k=0; k<19; k=k+1) raw_pipe[k] <= 0;
        end else begin
            raw_pipe[0] <= raw_frame;
            for (k=1; k<19; k=k+1) raw_pipe[k] <= raw_pipe[k-1];
            raw_valid_pipe <= {raw_valid_pipe[17:0],frame_valid};
            if (raw_valid_pipe[18]) control_raw_frame <= raw_pipe[18];
        end
    end
// synthesis translate_off
`ifndef SYNTHESIS
    initial if (ACTIVE_KEYS != 1 && ACTIVE_KEYS != 4 && ACTIVE_KEYS != 8)
        $fatal(1, "ACTIVE_KEYS must be 1, 4 or 8");
    always @(posedge clk) if (rst_n && !frame_cancel) begin
        for (integer n=1; n<ACTIVE_KEYS; n=n+1)
            if (lane_valid[n] !== lane_valid[0])
                $fatal(1, "Per-key pipeline validity diverged");
    end
`endif
// synthesis translate_on
endmodule
`default_nettype wire
