`timescale 1ns/1ps
`default_nettype none

// One MCP3208 single-ended conversion. All registers use the 50 MHz clk.
// start/channel must already be synchronous to clk. Pulse start for one cycle;
// it is accepted only in IDLE. Busy-time pulses are discarded, not queued.
// A start held into the next IDLE is a new request (not an edge detector).
// channel is captured as part of the command when the request is accepted.
// After reset an early request is accepted, but CS waits for a 2 us high guard.
// data changes only on reset or valid; valid lasts one clk cycle, busy is then 0.
// This module does not schedule scans or publish an eight-channel control frame.
module adc_spi (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [2:0]  channel,
    input  wire        miso,
    output reg         cs_n,
    output reg         sclk,
    output reg         mosi,
    output reg         busy,
    output reg  [11:0] data,
    output reg         valid
);
    // Fixed project timing: 50 MHz / (2*50) = 500 kHz.
    // Separate counters/limits keep the 2 us gap from changing SPI frequency.
    localparam integer HALF_CYCLES = 50;
    localparam integer CS_HIGH_CYCLES = 100;
    localparam [2:0] IDLE = 3'd0, SHIFT = 3'd1,
                     HOLD = 3'd2, GAP = 3'd3, WAIT_HIGH = 3'd4;

    reg [2:0] state;
    reg [6:0] count; // Must represent 99 for the 100-cycle CS-high gap.
    reg [4:0] bit_index;
    reg [23:0] tx_shift;
    reg [11:0] rx_shift;
    reg miso_meta;
    reg miso_sync;

    // DOUT changes after the external falling SCLK edge. At 500 kHz the
    // 1 us half-cycle allows the modeled 200 ns DOUT delay plus this pipeline.
    // RTL simulation does not prove metastability MTBF or physical IO timing.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            miso_meta <= 1'b0;
            miso_sync <= 1'b0;
        end else begin
            miso_meta <= miso;
            miso_sync <= miso_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count <= 7'd0;
            bit_index <= 5'd0;
            tx_shift <= 24'd0;
            rx_shift <= 12'd0;
            cs_n <= 1'b1;
            sclk <= 1'b0;
            mosi <= 1'b0;
            busy <= 1'b0;
            data <= 12'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                IDLE: begin
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    mosi <= 1'b0;
                    // Saturating reset-recovery guard. Normal GAP completion
                    // preloads 100, so it does not add a second normal gap.
                    // 101 observed edges span >=100 full periods even when
                    // reset deassertion is asynchronous to clk.
                    if (count < CS_HIGH_CYCLES)
                        count <= count + 7'd1;
                    if (start) begin
                        // [23:19]=0, [18]=Start, [17]=single-ended,
                        // [16:14]=channel. CH0=060000, CH1=064000.
                        tx_shift <= {5'b00000, 2'b11, channel, 14'd0};
                        rx_shift <= 12'd0;
                        bit_index <= 5'd0;
                        busy <= 1'b1;
                        if (count == CS_HIGH_CYCLES) begin
                            count <= 7'd0;
                            cs_n <= 1'b0;
                            state <= SHIFT;
                        end else begin
                            state <= WAIT_HIGH;
                        end
                    end
                end
                WAIT_HIGH: begin
                    if (count == CS_HIGH_CYCLES) begin
                        count <= 7'd0;
                        cs_n <= 1'b0;
                        state <= SHIFT;
                    end else begin
                        count <= count + 7'd1;
                    end
                end
                SHIFT: begin
                    if (count == HALF_CYCLES - 1) begin
                        count <= 7'd0;
                        if (!sclk) begin
                            sclk <= 1'b1;
                            // Zero-based 12..23 = rising edges 13..24.
                            // Ignore the unknown prefix and edge-12 null.
                            if (bit_index >= 5'd12)
                                rx_shift <= {rx_shift[10:0], miso_sync};
                        end else begin
                            sclk <= 1'b0;
                            if (bit_index == 5'd23) begin
                                state <= HOLD;
                            end else begin
                                mosi <= tx_shift[22];
                                tx_shift <= {tx_shift[22:0], 1'b0};
                                bit_index <= bit_index + 5'd1;
                            end
                        end
                    end else begin
                        count <= count + 7'd1;
                    end
                end
                HOLD: begin
                    // Keep CS low for 1 us after the final falling SCLK edge.
                    if (count == HALF_CYCLES - 1) begin
                        count <= 7'd0;
                        cs_n <= 1'b1;
                        mosi <= 1'b0;
                        state <= GAP;
                    end else begin
                        count <= count + 7'd1;
                    end
                end
                GAP: begin
                    // Remain busy until CS has been high for 2 us.
                    // The earliest next acceptance adds another clk cycle.
                    if (count == CS_HIGH_CYCLES - 1) begin
                        count <= 7'd100;
                        data <= rx_shift; // B0 was captured earlier in SHIFT.
                        valid <= 1'b1;
                        busy <= 1'b0;
                        state <= IDLE;
                    end else begin
                        count <= count + 7'd1;
                    end
                end
                default: begin
                    state <= IDLE;
                    count <= 7'd0;
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    mosi <= 1'b0;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
