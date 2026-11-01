`timescale 1ns/1ps

// Eight independent active-high LEDs; no generated clock.
// All inputs are synchronous to clk. rst_n is the common released reset.
// At every enabled rising edge, led samples target_mask and brightness using
// the phase BEFORE that edge. The phase advances once per PWM_DIV clocks.
// brightness=0: always off; 255: always on; 1..254: brightness/256 duty.
// enable=0 resets both phase/divider and clears led at the next rising edge.
// Reset assertion clears led and PWM state asynchronously.
module led_driver #(
    parameter integer PWM_DIV = 50
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] target_mask,
    input  wire [7:0] brightness,
    output reg  [7:0] led
);
    // The safe value prevents illegal widths even when an invalid parameter
    // is supplied. Simulation still rejects the invalid configuration.
    localparam integer DIV_CYCLES = (PWM_DIV < 1) ? 1 : PWM_DIV;
    localparam integer DIV_WIDTH = (DIV_CYCLES < 2) ? 1 : $clog2(DIV_CYCLES);

    reg [DIV_WIDTH-1:0] div_count;
    reg [7:0] phase;

`ifndef SYNTHESIS
    initial begin
        if (PWM_DIV < 1)
            $fatal(1, "led_driver: PWM_DIV must be >= 1");
    end
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_count <= {DIV_WIDTH{1'b0}};
            phase     <= 8'd0;
            led       <= 8'd0;
        end else if (!enable) begin
            div_count <= {DIV_WIDTH{1'b0}};
            phase     <= 8'd0;
            led       <= 8'd0;
        end else begin
            if (div_count == DIV_CYCLES - 1) begin
                div_count <= {DIV_WIDTH{1'b0}};
                phase     <= phase + 8'd1;
            end else begin
                div_count <= div_count + 1'b1;
            end

            if ((brightness == 8'd255) ||
                ((brightness != 8'd0) && (phase < brightness)))
                led <= target_mask;
            else
                led <= 8'd0;
        end
    end
endmodule
