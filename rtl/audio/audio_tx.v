module audio_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] sample_data,
    output reg         bclk,
    output wire        ws,
    output reg         din,
    output reg         sample_ce,
    // High BEFORE the clock edge that starts a frame. It is an enable,
    // not a clock. Named instances using the old ports may leave it open.
    output wire        frame_start
);
    reg [2:0]  div_cnt;
    reg [5:0]  bit_cnt;
    reg [15:0] frame_sample;
    reg        started;
    wire [5:0] next_bit;

    assign ws = bit_cnt[5];
    assign next_bit = bit_cnt + 6'd1;
    assign frame_start = rst_n &&
        (!started || ((div_cnt == 3'd7) && bclk && (bit_cnt == 6'd63)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt      <= 3'd0;
            bit_cnt      <= 6'd0;
            frame_sample <= 16'd0;
            started      <= 1'b0;
            bclk         <= 1'b0;
            din          <= 1'b0;
            sample_ce    <= 1'b0;
        end else begin
            sample_ce <= 1'b0;
            if (!started) begin
                started   <= 1'b1;
                sample_ce <= 1'b1;
            end else if (div_cnt == 3'd7) begin
                div_cnt <= 3'd0;
                bclk    <= ~bclk;
                if (bclk == 1'b1) begin
                    bit_cnt <= next_bit;
                    if (next_bit == 6'd0) begin
                        frame_sample <= sample_data;
                        sample_ce    <= 1'b1;
                    end
                    if ((next_bit[4:0] >= 5'd1) &&
                        (next_bit[4:0] <= 5'd16))
                        din <= frame_sample[5'd16 - next_bit[4:0]];
                    else
                        din <= 1'b0;
                end
            end else begin
                div_cnt <= div_cnt + 3'd1;
            end
        end
    end
endmodule
