module audio_tx (
    input  wire        clk,         // 50 MHz主时钟
    input  wire        rst_n,       // 低电平复位
    input  wire [15:0] sample_data, // 待发送的16位样本

    output reg         bclk,
    output wire        ws,
    output reg         din,
    output reg         sample_ce   // 每帧一次，持续一个主时钟周期
);

    reg [2:0]  div_cnt;
    reg [5:0]  bit_cnt;
    reg [15:0] frame_sample;
    reg        started;

    wire [5:0] next_bit;

    assign ws       = bit_cnt[5];
    assign next_bit = bit_cnt + 6'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt     <= 3'd0;
            bit_cnt     <= 6'd0;
            frame_sample <= 16'd0;
            started     <= 1'b0;
            bclk        <= 1'b0;
            din         <= 1'b0;
            sample_ce   <= 1'b0;
        end
        else begin
            // 默认拉低，保证请求脉冲只持续一个周期
            sample_ce <= 1'b0;

            if (!started) begin
                // 开始第一帧，发送复位时保存的零样本
                started   <= 1'b1;
                sample_ce <= 1'b1;
            end
            else if (div_cnt == 3'd7) begin
                div_cnt <= 3'd0;
                bclk    <= ~bclk;

                // 原来的BCLK为1，这次将产生下降沿
                if (bclk == 1'b1) begin
                    bit_cnt <= next_bit;

                    if (next_bit == 6'd0) begin
                        // 新帧开始，锁存样本并发出下一次请求
                        frame_sample <= sample_data;
                        sample_ce    <= 1'b1;
                    end

                    // 每个声道的位置1到16发送D15到D0
                    if ((next_bit[4:0] >= 5'd1) &&
                        (next_bit[4:0] <= 5'd16)) begin
                        din <= frame_sample[
                            5'd16 - next_bit[4:0]
                        ];
                    end
                    else begin
                        // 位置0是延迟位，位置17到31补零
                        din <= 1'b0;
                    end
                end
            end
            else begin
                div_cnt <= div_cnt + 3'd1;
            end
        end
    end

endmodule