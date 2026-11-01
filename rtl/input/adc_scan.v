`timescale 1ns/1ps
`default_nettype none
// Synthesizable module wrapper, not a board top (no pin/LED/clock constraints).
// raw_frame[11:0]=CH0 ... raw_frame[95:84]=CH7, all 12-bit unsigned.
// frame_valid/scan_start/timeout are single clk pulses. raw_frame holds between
// publications, including timeouts; global reset clears it and all diagnostics.
// Raw ADC frames require later calibration/mapping before gate/key_gain use.
module adc_scan (
    input wire clk,
    input wire rst_n,
    input wire miso,
    output wire cs_n,
    output wire sclk,
    output wire mosi,
    output wire [95:0] raw_frame,
    output wire frame_valid,
    output wire scan_start,
    output wire scan_busy,
    output wire timeout,
    output wire [31:0] timeout_count
);
    wire spi_start, spi_busy, spi_valid, spi_abort;
    wire [2:0] spi_channel;
    wire [11:0] spi_data;
    // Controller abort resets only the SPI engine. Keep the last published raw
    // frame and timeout count. System top is responsible for global reset release.
    wire spi_rst_n = rst_n & ~spi_abort;
    adc_spi spi (.clk(clk), .rst_n(spi_rst_n), .start(spi_start),
        .channel(spi_channel), .miso(miso), .cs_n(cs_n), .sclk(sclk),
        .mosi(mosi), .busy(spi_busy), .data(spi_data), .valid(spi_valid));
    adc_scan_controller controller (.clk(clk), .rst_n(rst_n),
        .spi_busy(spi_busy), .spi_valid(spi_valid), .spi_data(spi_data),
        .spi_start(spi_start), .spi_channel(spi_channel), .spi_abort(spi_abort),
        .raw_frame(raw_frame), .frame_valid(frame_valid), .scan_start(scan_start),
        .scan_busy(scan_busy), .timeout(timeout), .timeout_count(timeout_count));
endmodule
`default_nettype wire
