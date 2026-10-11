module single_voice_core #(
    parameter ROM_FILE = "tables/sine_1024_16bit.hex"
)(
    input  wire               clk,
    input  wire               rst_n,

    // 每个音频采样对应一次请求
    input  wire               sample_ce,

    // 相位步长：决定音高
    input  wire [31:0]        phase_step,

    // 八键控制接口，本阶段只使用通道0
    input  wire [7:0]         gate,
    input  wire [127:0]       key_gain,
    input  wire               controls_valid,

    // 输出给后续音频模块
    output reg signed [15:0]  mixed_sample,
    output reg                mixed_valid
);

    // --------------------------------------------------
    // 1. 保存最近收到的完整控制帧
    // --------------------------------------------------

    reg [7:0]   gate_saved;
    reg [127:0] gain_saved;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_saved <= 8'd0;
            gain_saved <= 128'd0;
        end else if (controls_valid) begin
            gate_saved <= gate;
            gain_saved <= key_gain;
        end
    end

    // --------------------------------------------------
    // 2. 正弦波表
    // 1024个采样，每个采样16位有符号
    // --------------------------------------------------

    reg signed [15:0] sine_rom [0:1023];

    initial begin
        $readmemh(ROM_FILE, sine_rom);
    end

    // --------------------------------------------------
    // 3. 相位累加器与第一流水级
    // --------------------------------------------------

    reg [31:0] phase_q;

    wire [9:0] rom_addr;
    assign rom_addr = phase_q[31:22];

    // 同一次采样的波形、gate、gain一起登记
    reg signed [15:0] wave_q;
    reg               gate_q;
    reg [15:0]        gain_q;
    reg               wave_valid_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_q      <= 32'd0;
            wave_q       <= 16'sd0;
            gate_q       <= 1'b0;
            gain_q       <= 16'd0;
            wave_valid_q <= 1'b0;
        end else begin
            wave_valid_q <= sample_ce;

            if (sample_ce) begin
                // 使用更新前的相位读取波表
                wave_q <= sine_rom[rom_addr];

                // 同时锁定本次采样使用的控制
                gate_q <= gate_saved[0];
                gain_q <= gain_saved[15:0];

                // 下一次采样使用新的相位
                phase_q <= phase_q + phase_step;
            end
        end
    end

    // --------------------------------------------------
    // 4. 有符号乘法和缩放
    // --------------------------------------------------

    // 16位无符号gain补零，变成17位非负signed
    wire signed [16:0] gain_signed;
    assign gain_signed = $signed({1'b0, gain_q});

    // 16位 × 17位，保留33位乘积
    wire signed [32:0] product;
    assign product = wave_q * gain_signed;

    // 实际比例 = gain / 65536
    wire signed [32:0] scaled;
    assign scaled = product >>> 16;

    // --------------------------------------------------
    // 5. 第二流水级：登记最终输出
    // --------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mixed_sample <= 16'sd0;
            mixed_valid  <= 1'b0;
        end else begin
            mixed_valid <= wave_valid_q;

            if (wave_valid_q) begin
                if (gate_q)
                    mixed_sample <= scaled[15:0];
                else
                    mixed_sample <= 16'sd0;
            end
        end
    end

endmodule