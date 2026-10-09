// Tang Mega 60K NEO: a minimal 440 Hz mono tone for the onboard PT8211-S DAC.
// sys_clk is the dock's 50 MHz clock. The first build deliberately uses no PLL.
module top (
    input  wire sys_clk,
    input  wire rst_n,
    output reg  i2s_bclk,
    output reg  i2s_lrck,
    output reg  i2s_din,
    output wire pa_en
);
    // PT8211-S uses 16-bit LSB-justified stereo words, sampled on BCLK rising.
    // BCLK = 50 MHz / 32 = 1.5625 MHz; sample rate = BCLK / 32 = 48,828.125 Hz.
    // DDS step = round(440 * 2^32 / 48,828.125) = 38,702,809.
    localparam [31:0] PHASE_STEP = 32'd38702809;
    localparam signed [15:0] LEVEL = 16'sd50;

    reg [3:0] div_count;
    reg [4:0] bit_index;
    reg [31:0] phase;
    reg signed [15:0] sample;
    wire signed [15:0] next_sample = phase[31] ? -LEVEL : LEVEL;

    // The NEO schematic labels PA_EN=0 as amplifier on.
    assign pa_en = 1'b0;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            div_count <= 4'd0;
            bit_index <= 5'd0;
            phase <= 32'd0;
            sample <= 16'sd0;
            i2s_bclk <= 1'b1;
            i2s_lrck <= 1'b0;
            i2s_din <= 1'b0;
        end else if (div_count == 4'd15) begin
            div_count <= 4'd0;
            i2s_bclk <= ~i2s_bclk;
            // Set WS and DIN at falling BCLK; the DAC reads at the next rising edge.
            if (i2s_bclk) begin
                i2s_lrck <= bit_index[4];
                if (bit_index == 5'd0) begin
                    sample <= next_sample;
                    phase <= phase + PHASE_STEP;
                    i2s_din <= next_sample[15];
                end else begin
                    i2s_din <= sample[15 - bit_index[3:0]];
                end
                bit_index <= bit_index + 5'd1;
            end
        end else begin
            div_count <= div_count + 4'd1;
        end
    end
endmodule
