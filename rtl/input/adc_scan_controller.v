`timescale 1ns/1ps
`default_nettype none
// Eight single-ended ADC reads per 1 ms. 50 MHz synchronous SPI-side handshake.
// Separate controller ports allow a stalled SPI handshake to be tested without
// forcing DUT internals. MISO alone cannot stall the existing fixed-length SPI.
module adc_scan_controller (
    input wire clk,
    input wire rst_n,
    input wire spi_busy,
    input wire spi_valid,
    input wire [11:0] spi_data,
    output reg spi_start,
    output reg [2:0] spi_channel,
    output reg spi_abort,
    output reg [95:0] raw_frame,
    output reg frame_valid,
    output reg scan_start,
    output reg scan_busy,
    output reg timeout,
    output reg [31:0] timeout_count
);
    localparam [1:0] IDLE = 2'd0, ISSUE = 2'd1, WAIT_RESULT = 2'd2;
    localparam [15:0] PERIOD_LAST = 16'd49999;
    reg [1:0] state;
    reg [15:0] period_count;
    reg [95:0] shadow_frame;
    wire period_tick = (period_count == PERIOD_LAST);

    // First attempt is on the 50,000th active clock after reset release.
    // The periodic grid never shifts with completion time or a timeout.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) period_count <= 16'd0;
        else if (period_tick) period_count <= 16'd0;
        else period_count <= period_count + 16'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            shadow_frame <= 96'd0;
            raw_frame <= 96'd0;
            spi_start <= 1'b0;
            spi_channel <= 3'd0;
            spi_abort <= 1'b0;
            frame_valid <= 1'b0;
            scan_start <= 1'b0;
            scan_busy <= 1'b0;
            timeout <= 1'b0;
            timeout_count <= 32'd0;
        end else begin
            spi_start <= 1'b0;
            spi_abort <= 1'b0;
            frame_valid <= 1'b0;
            scan_start <= 1'b0;
            timeout <= 1'b0;
            // Deadline wins over a coincident result, including CH7.
            // A failed round is discarded; do not start another on this tick.
            // Retry CH0 at the following 1 ms tick after the abort pulse.
            if (period_tick && state != IDLE) begin
                state <= IDLE;
                scan_busy <= 1'b0;
                shadow_frame <= 96'd0;
                spi_channel <= 3'd0;
                spi_abort <= 1'b1;
                timeout <= 1'b1;
                if (timeout_count != 32'hffffffff)
                    timeout_count <= timeout_count + 32'd1;
            end else begin
                case (state)
                    IDLE: begin
                        if (period_tick) begin
                            scan_start <= 1'b1;
                            scan_busy <= 1'b1;
                            shadow_frame <= 96'd0;
                            spi_channel <= 3'd0;
                            state <= ISSUE;
                        end
                    end
                    ISSUE: begin
                        if (!spi_busy) begin
                            spi_start <= 1'b1;
                            state <= WAIT_RESULT;
                        end
                    end
                    WAIT_RESULT: begin
                        if (spi_valid) begin
                            if (spi_channel == 3'd7) begin
                                // Include the CURRENT CH7 result; do not read
                                // an old shadow[95:84] on the same NBA edge.
                                raw_frame <= {spi_data, shadow_frame[83:0]};
                                frame_valid <= 1'b1;
                                scan_busy <= 1'b0;
                                state <= IDLE;
                            end else begin
                                shadow_frame[12*spi_channel +: 12] <= spi_data;
                                spi_channel <= spi_channel + 3'd1;
                                state <= ISSUE;
                            end
                        end
                    end
                    default: begin
                        state <= IDLE;
                        scan_busy <= 1'b0;
                        shadow_frame <= 96'd0;
                        spi_abort <= 1'b1;
                    end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
