// 独立参考模块：不修改 DDS.v，也不覆盖用户的 wave_rom.v。
// 默认 ROM_FILE 以项目根目录作为仿真运行目录。
module wave_rom_example #(
    parameter ROM_FILE = "tables/sine_1024_16bit.hex"
)(
    input  wire               sys_clk,
    input  wire               rst_n,
    input  wire               sample_ce,
    input  wire [31:0]        phase,

    output reg signed [15:0]  wave_sample,
    output reg               wave_valid
);

    // 1024 = 2^10，使用相位高 10 位选择波表地址。
    wire [9:0] addr;
    assign addr = phase[31:22];

    // 一周期波形，1024 个点，每点 16 位有符号补码。
    reg signed [15:0] rom [0:1023];

    // 只初始化存储内容；运行中不写入 ROM。
    initial begin
        $readmemh(ROM_FILE, rom);
    end

    // 同步读取：采样请求的上升沿后更新数据及有效标志。
    // 与 DDS 同一沿工作时，这里使用的是更新前的 phase。
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            wave_sample <= 16'sd0;
            wave_valid  <= 1'b0;
        end else begin
            wave_valid <= sample_ce;

            if (sample_ce)
                wave_sample <= rom[addr];
        end
    end

endmodule