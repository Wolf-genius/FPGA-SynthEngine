module adc_ch0 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        miso,

    output reg         cs_n,
    output reg         sclk,
    output reg         mosi,
    output reg         busy,
    output reg  [11:0] data,
    output reg         valid
);

    // 50MHz / (2 * 50) = 500kHz
    localparam integer HALF_CYCLES = 50;
    localparam [23:0] COMMAND = 24'h060000;

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] SHIFT = 2'd1;
    localparam [1:0] HOLD  = 2'd2;
    localparam [1:0] GAP   = 2'd3;

    reg [1:0]  state;
    reg [5:0]  count;
    reg [4:0]  bit_index;
    reg [11:0] rx_data;

    reg miso_meta;
    reg miso_sync;

    // MISO先进入主时钟域。
    // 默认SPI半周期为1us，留有两级寄存器延迟余量。
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
            state     <= IDLE;
            count     <= 0;
            bit_index <= 0;
            rx_data   <= 0;
            cs_n      <= 1'b1;
            sclk      <= 1'b0;
            mosi      <= 1'b0;
            busy      <= 1'b0;
            data      <= 0;
            valid     <= 1'b0;
        end else begin
            // valid默认拉低，只在完成时拉高一周期。
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    mosi <= 1'b0;

                    if (start) begin
                        cs_n      <= 1'b0;
                        busy      <= 1'b1;
                        count     <= 0;
                        bit_index <= 0;
                        rx_data   <= 0;
                        mosi      <= COMMAND[23];
                        state     <= SHIFT;
                    end
                end

                SHIFT: begin
                    if (count == HALF_CYCLES - 1) begin
                        count <= 0;

                        if (sclk == 1'b0) begin
                            // 产生SPI上升沿，接收数据。
                            sclk <= 1'b1;

                            // bit_index从0开始：
                            // 12～23对应第13～24个上升沿。
                            if (bit_index >= 12)
                                rx_data <= {
                                    rx_data[10:0], miso_sync
                                };
                        end else begin
                            // 产生SPI下降沿，准备下一位命令。
                            sclk <= 1'b0;

                            if (bit_index == 23) begin
                                state <= HOLD;
                            end else begin
                                mosi <= COMMAND[22 - bit_index];
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                HOLD: begin
                    // 最后一个时钟结束后，保持CS低约1us。
                    if (count == HALF_CYCLES - 1) begin
                        count <= 0;
                        cs_n  <= 1'b1;
                        mosi  <= 1'b0;
                        state <= GAP;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                GAP: begin
                    // 保证事务之间有约1us的CS高电平。
                    if (count == HALF_CYCLES - 1) begin
                        count <= 0;
                        data  <= rx_data;
                        valid <= 1'b1;
                        busy  <= 1'b0;
                        state <= IDLE;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    cs_n  <= 1'b1;
                    sclk  <= 1'b0;
                    mosi  <= 1'b0;
                    busy  <= 1'b0;
                    count <= 0;
                end
            endcase
        end
    end
endmodule