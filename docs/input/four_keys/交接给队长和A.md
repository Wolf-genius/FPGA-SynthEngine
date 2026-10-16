> 此文的src/tb/sim等路径保留原始ZIP布局；仓库文件位置及运行入口见rtl/input/README.md。

# B输入交接：前四键，完整八键接口

计划日期10/15～18，代码实际交付2026-10-16。源码清单见根目录rtl.f。无需新增外部GPIO；复用现有PMOD0 SPI，由A保持正式MISO输入、统一复位释放和CST/SDC。现有成功一键工程未被本包覆盖。

## A如何接真实输入

将旧的一键输入实例替换为下例，声音核心、音频缓冲及I2S继续由各负责人维护：

```verilog
wire [7:0] b_gate;
wire [127:0] b_gain;
wire b_valid;
wire [95:0] b_raw, b_control_raw;
wire b_raw_valid, b_scan_start, b_scan_busy, b_timeout;
wire [31:0] b_timeout_count;
pressure_keys_input #(.ACTIVE_KEYS(4)) b_input (
    .clk(clk), .rst_n(rst_n), .miso(adc_miso),
    .cs_n(adc_cs_n), .sclk(adc_sclk), .mosi(adc_mosi),
    .gate(b_gate), .key_gain(b_gain), .controls_valid(b_valid),
    .raw_frame(b_raw), .frame_valid(b_raw_valid),
    .control_raw_frame(b_control_raw),
    .scan_start(b_scan_start), .scan_busy(b_scan_busy),
    .timeout(b_timeout), .timeout_count(b_timeout_count)
);
// 将b_gate/b_gain/b_valid连接到队长核心，不再读取某一路raw来控制全局音量。
```

六份正式RTL和现有同名ADC模块避免重复加入。tb/sim下的模型、向量和测试不能编入Gowin。fake_four_key_controls仅在独立测试top或明确选择的测试分支使用，真实模式复位保持零。

## 每键校准参数如何填

参数为编译期常量，12位表有8个条目，16位最小力度表同理：

```verilog
// 下例只是打包次序；TON_CHx等必须由实测校准常量定义。
.TON_PACK({TON_CH7, TON_CH6, TON_CH5, TON_CH4,
           TON_CH3, TON_CH2, TON_CH1, TON_CH0})
// 每个TON_CHx显式定义为12位，例如localparam [11:0] TON_CH0=...;
```

四键阶段只启用CH0～3；其余四路即使raw=4095仍输出gate/gain零。所有八个原始通道继续扫描、原始快照保留，方便后续扩展。不要把仿真中的非一致八路参数当作实测四键校准值。

## 队长如何先验证ADSR

接 `examples/fake_four_key_controls.v` 的三路控制输出；默认每1ms发布。400帧循环：

| 帧编号 | gate | 动作 |
|---|---|---|
| 0～9 | 00 | 静音 |
| 10～29 | 01 | 单键按住 |
| 30～49 | 03 | 两键按住 |
| 50～129 | 0F | 四键长按，力度均32768 |
| 130～149 | 0D | 只松第二键，同时第二键力度变0 |
| 150～169 | 0F | 第二键在100ms释放期间重按 |
| 170～184 | 0F | 只将第三键力度改为49152 |
| 185～199 | 0F | 只将第三键力度改为16384 |
| 200～209 | 0E/0F交替 | 第一键快速重复 |
| 210～399 | 00 | 全松开，留190ms收尾时间 |

这些是发给核心的测试输入，未证明现有核心已通过ADSR。必须检查：第二键单独Release，其他三路继续；释放零力度不截尾；重按从当前包络Attack；力度改变只影响第三声部；相位连续；输出valid与音频样本对齐。起音中提前松开等核心边界仍由队长专项TB覆盖。

核心先每50MHz拍在controls_valid整体锁存，再sample_ce使用旧锁存值。例化control_frame_receiver可观察这一规则，但它只输出控制快照，不输出声音，不实现力度冻结。核心要独立保存每声部最近按住力度，不能将本次松手的零力度覆盖收尾值。

## 四键实物联调

B先将CH0～3原始值、gate位和对应16位gain交A观察。按单键→两键→四键→只松第二键→只改变第三键力度→快速重按执行。只有raw/gate/gain正确时，再判断核心ADSR及混音；录音/听感不能替代完整数字帧和数值校准。实物结果写现场CSV，不填仿真数据。

历史接口v1副本已定位于tmp/FPGA-input-upload/docs；本交付依根AGENTS及现行2.0/每日手册，不把历史副本当作新的团队审批。B完成输入代码，A继续总工程/PnR/实物，队长继续ADSR/四voice/mixer。
