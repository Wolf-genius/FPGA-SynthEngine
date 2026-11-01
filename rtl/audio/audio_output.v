// Connect the real synthesis core here after its actual interface is checked.
// clk is 50 MHz. rst_n must be the shared, synchronously released reset.
module audio_output (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] mixed_data,
    input  wire        mixed_valid,
    output wire        sample_ce,
    output wire        bclk,
    output wire        ws,
    output wire        din,
    output wire        frame_tick,
    output wire [31:0] underrun_count,
    output wire [31:0] discarded_count
);
    wire frame_start;
    wire [15:0] sample_data;
    audio_sample_buffer buffer (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .mixed_data(mixed_data), .mixed_valid(mixed_valid),
        .sample_ce(sample_ce), .sample_data(sample_data),
        .underrun_count(underrun_count), .discarded_count(discarded_count)
    );
    audio_tx transmitter (
        .clk(clk), .rst_n(rst_n), .sample_data(sample_data),
        .bclk(bclk), .ws(ws), .din(din),
        .sample_ce(frame_tick), .frame_start(frame_start)
    );
endmodule
