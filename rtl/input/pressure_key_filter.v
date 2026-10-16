`timescale 1ns/1ps
`default_nettype none
// Adapted from one_key/rtl/input/pressure_ch0_controls.v; arithmetic unchanged.
// Exact pressure mapping with registered multiply and restoring division.
// Accepts one raw sample per clock; publishes at acceptance edge E+19
// (380 ns at 50 MHz), with the same arithmetic as the source implementation.
module pressure_key_filter #(
    parameter [11:0] TON = 12'd256, TOFF = 12'd128,
    parameter [11:0] RAW_MIN = 12'd128, RAW_MAX = 12'd3840,
    parameter [15:0] MIN_GAIN = 16'd4096
)(
    input wire clk, rst_n,
    input wire [11:0] raw_data,
    input wire raw_valid,
    // Synchronous failed-round notification: flush pending work/confirmation;
    // preserve the last held state and smoothing history. Priority over raw_valid.
    input wire frame_cancel,
    output reg gate,
    output reg [15:0] key_gain,
    output reg controls_valid
);
    localparam [11:0] SPAN = RAW_MAX - RAW_MIN;
    localparam [15:0] GAIN_SPAN = 16'd65535 - MIN_GAIN;
    // Clamp and subtract before the registered multiply. The two endpoints
    // still map exactly to MIN_GAIN / 65535, including out-of-range inputs.
    reg [11:0] delta_raw, clamped_raw;
    reg clamp_valid;
    reg [27:0] product;
    reg [11:0] product_raw;
    reg product_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delta_raw <= 12'd0;
            clamped_raw <= 12'd0;
            clamp_valid <= 1'b0;
            product <= 28'd0;
            product_raw <= 12'd0;
            product_valid <= 1'b0;
        end else if (frame_cancel) begin
            clamp_valid <= 0; product_valid <= 0;
        end else begin
            clamp_valid <= raw_valid;
            if (raw_valid) begin
                clamped_raw <= raw_data;
                if (raw_data <= RAW_MIN) delta_raw <= 12'd0;
                else if (raw_data >= RAW_MAX) delta_raw <= SPAN;
                else delta_raw <= raw_data - RAW_MIN;
            end
            product_valid <= clamp_valid;
            if (clamp_valid) begin
                product <= delta_raw * GAIN_SPAN;
                product_raw <= clamped_raw;
            end
        end
    end
    // product <= SPAN * GAIN_SPAN < SPAN * 65536. Its high 12 bits
    // are already a remainder smaller than SPAN; 16 quotient bits remain.
    // Each stage computes ONE quotient bit with a 14-bit subtract.
    wire [11:0] remainder_pipe [0:16];
    wire [15:0] quotient_pipe [0:16];
    wire [11:0] raw_pipe [0:16];
    wire [16:0] valid_pipe;
    assign remainder_pipe[0] = product[27:16];
    assign quotient_pipe[0] = product[15:0];
    assign raw_pipe[0] = product_raw;
    assign valid_pipe[0] = product_valid;
    genvar bit_index;
    generate
        for (bit_index=0; bit_index<16; bit_index=bit_index+1) begin: divide_bit
            wire [12:0] shifted_remainder;
            wire [13:0] difference;
            wire quotient_bit;
            reg [11:0] remainder_reg;
            reg [15:0] quotient_reg;
            reg [11:0] raw_reg;
            reg valid_reg;
            assign shifted_remainder = {remainder_pipe[bit_index],
                                         quotient_pipe[bit_index][15]};
            assign difference = {1'b0, shifted_remainder} - {2'b00, SPAN};
            assign quotient_bit = ~difference[13];
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    remainder_reg <= 12'd0;
                    quotient_reg <= 16'd0;
                    raw_reg <= 12'd0;
                    valid_reg <= 1'b0;
                end else if (frame_cancel) begin
                    valid_reg <= 0;
                end else begin
                    valid_reg <= valid_pipe[bit_index];
                    if (valid_pipe[bit_index]) begin
                        remainder_reg <= quotient_bit ? difference[11:0]
                                                       : shifted_remainder[11:0];
                        quotient_reg <= {quotient_pipe[bit_index][14:0],
                                         quotient_bit};
                        raw_reg <= raw_pipe[bit_index];
                    end
                end
            end
            assign remainder_pipe[bit_index+1] = remainder_reg;
            assign quotient_pipe[bit_index+1] = quotient_reg;
            assign raw_pipe[bit_index+1] = raw_reg;
            assign valid_pipe[bit_index+1] = valid_reg;
        end
    endgenerate
    reg [15:0] mapped;
    reg [11:0] mapped_raw;
    reg mapped_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mapped <= 16'd0;
            mapped_raw <= 12'd0;
            mapped_valid <= 1'b0;
        end else if (frame_cancel) begin
            mapped_valid <= 0;
        end else begin
            mapped_valid <= valid_pipe[16];
            if (valid_pipe[16]) begin
                mapped <= MIN_GAIN + quotient_pipe[16];
                mapped_raw <= raw_pipe[16];
            end
        end
    end
    // State changes only when a valid sample retires. This preserves the
    // original confirmation and signed Q16.8 smoothing for contiguous input.
    reg confirm_one;
    reg [23:0] smooth_q8;
    reg next_gate, next_confirm;
    reg [23:0] base_q8, next_q8;
    reg signed [24:0] delta, stepped;
    reg [15:0] gain_next;
    reg [24:0] rounded;
    always @* begin
        next_gate = gate;
        next_confirm = 1'b0;
        if ((!gate && mapped_raw >= TON) ||
            (gate && mapped_raw <= TOFF)) begin
            if (confirm_one) next_gate = ~gate;
            else next_confirm = 1'b1;
        end
        base_q8 = gate ? smooth_q8 : {MIN_GAIN, 8'd0};
        delta = $signed({1'b0, mapped, 8'd0}) - $signed({1'b0, base_q8});
        stepped = $signed({1'b0, base_q8}) + delta / 25'sd4;
        next_q8 = next_gate ? stepped[23:0] : 24'd0;
        rounded = {1'b0, next_q8} + 25'd128;
        gain_next = rounded[23:8];
        if (next_gate && gain_next < MIN_GAIN) gain_next = MIN_GAIN;
        if (!next_gate) gain_next = 16'd0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate <= 1'b0;
            key_gain <= 16'd0;
            controls_valid <= 1'b0;
            confirm_one <= 1'b0;
            smooth_q8 <= 24'd0;
        end else if (frame_cancel) begin
            controls_valid <= 0; confirm_one <= 0;
        end else begin
            controls_valid <= mapped_valid;
            if (mapped_valid) begin
                gate <= next_gate;
                key_gain <= gain_next;
                confirm_one <= next_confirm;
                smooth_q8 <= next_q8;
            end
        end
    end
// synthesis translate_off
`ifndef SYNTHESIS
    initial begin
        if (TON <= TOFF || RAW_MAX <= RAW_MIN || MIN_GAIN == 0) begin
            $fatal(1, "Invalid pressure calibration parameters");
        end
    end
`endif
// synthesis translate_on
endmodule
`default_nettype wire
