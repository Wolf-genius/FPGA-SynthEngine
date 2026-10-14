`timescale 1ns/1ps
`default_nettype none
// Synchronous raw CH0 samples; no SPI, clock crossing or physical pins here.
module pressure_ch0_controls #(
    parameter [11:0] TON = 12'd256, TOFF = 12'd128,
    parameter [11:0] RAW_MIN = 12'd128, RAW_MAX = 12'd3840,
    parameter [15:0] MIN_GAIN = 16'd4096
)(
    input wire clk, rst_n,
    input wire [11:0] raw_data,
    input wire raw_valid,
    output reg [7:0] gate,
    output reg [127:0] key_gain,
    output reg controls_valid
);
    reg confirm_one;
    reg [23:0] smooth_q8;
    reg next_gate;
    reg next_confirm;
    reg [31:0] mapped, product;
    reg [23:0] base_q8, next_q8;
    reg signed [24:0] delta, stepped;
    reg [15:0] gain_next;
    reg [24:0] rounded;
    localparam [31:0] SPAN = {20'd0, RAW_MAX} - {20'd0, RAW_MIN};
    localparam [31:0] GAIN_SPAN = 32'd65535 - {16'd0, MIN_GAIN};

    always @* begin
        next_gate = gate[0];
        next_confirm = 1'b0;
        // Only consecutive VALID samples count; idle clocks do not count.
        if ((!gate[0] && raw_data >= TON) || (gate[0] && raw_data <= TOFF)) begin
            if (confirm_one) next_gate = ~gate[0];
            else next_confirm = 1'b1;
        end
        product = 32'd0;
        if (raw_data <= RAW_MIN) mapped = {16'd0, MIN_GAIN};
        else if (raw_data >= RAW_MAX) mapped = 32'd65535;
        else begin
            product = ({20'd0, raw_data} - {20'd0, RAW_MIN}) * GAIN_SPAN;
            mapped = {16'd0, MIN_GAIN} + product / SPAN;
        end
        // Q16.8: retain fractional gain; signed difference supports decreases.
        base_q8 = gate[0] ? smooth_q8 : {MIN_GAIN, 8'd0};
        delta = $signed({1'b0, mapped[15:0], 8'd0}) - $signed({1'b0, base_q8});
        stepped = $signed({1'b0, base_q8}) + delta / 25'sd4;
        next_q8 = next_gate ? stepped[23:0] : 24'd0;
        rounded = {1'b0, next_q8} + 25'd128;
        gain_next = rounded[23:8];
        if (next_gate && gain_next < MIN_GAIN) gain_next = MIN_GAIN;
        if (!next_gate) gain_next = 16'd0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate <= 8'd0;
            key_gain <= 128'd0;
            controls_valid <= 1'b0;
            confirm_one <= 1'b0;
            smooth_q8 <= 24'd0;
        end else begin
            controls_valid <= raw_valid;
            if (raw_valid) begin
                gate <= {7'd0, next_gate};
                key_gain <= {112'd0, gain_next};
                confirm_one <= next_confirm;
                smooth_q8 <= next_q8;
            end
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (TON <= TOFF || RAW_MAX <= RAW_MIN || MIN_GAIN == 0)
            $fatal(1, "Invalid pressure calibration parameters");
    end
`endif
endmodule
`default_nettype wire
