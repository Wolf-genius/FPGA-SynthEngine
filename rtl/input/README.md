# B：演奏输入

## 四键输入交付（2026-10-16）

正式入口改用`pressure_keys_input #(.ACTIVE_KEYS(4))`，向核心输出原有gate[7:0]、key_gain[127:0]、controls_valid。默认CH0～3独立处理、CH4～7输出零；ACTIVE_KEYS可选1/4/8，八路原始ADC仍完整扫描。原成功一键模块保留，二者不能同时驱动同一SPI/控制总线。

综合从仓库根目录按`rtl/input/pressure_keys.f`加入六份RTL：adc_spi、adc_scan_controller、adc_scan、pressure_key_filter、pressure_frame_controls、pressure_keys_input。同名模块只加入一份，不编入TB或旧labs副本。`examples/input/fake_four_key_controls.v`供队长先测四键保持、只松第二键、释放重按、只变第三键力度和快速重复；与真实源择一使用。接收规则参考已有control_frame_receiver。

主时钟50MHz，ADC Mode0/500kHz/24拍，每1ms整组扫描。每键编译期参数独立；默认TON/TOFF/RAW_MIN/RAW_MAX/MIN_GAIN=256/128/128/3840/4096，都是占位值。实现两轮确认、滞回、整数映射和Q16.8有符号1/4平滑；松开同帧gate/gain归零，核心须冻结此前力度进入Release。扫描超时保留上一完整控制帧，取消在途处理并清确认，恢复后重新两轮；不是物理断线检测。

完整raw发布到控制发布20拍/400ns，控制处理接受到发布19拍/380ns；消费者下一沿整体接收。controls_valid与sample_ce同沿时当前采样用旧帧，下个采样用新帧。详细端口与例化见[交接说明](../../docs/input/four_keys/交接给队长和A.md)。

仿真、综合脚本已按仓库目录重排并重新运行，入口见[tb/input说明](../../tb/input/README.md)。原始ZIP与完整历史波形/构建证据另归档在`deliveries/20261016/`。默认校准值未实测；本次只完成B输入代码与输入模块综合，不代表ADSR核心、PnR/物理时序、四键实物或整机≤10ms通过。

## 本次交付：CH0压力控制（2026-10-14）

正式RTL加入最终工程：

- `pressure_ch0_controls.v`：独立压力处理，无子模块依赖。输入同步的12位无符号`raw_data`与`raw_valid`，输出`gate[7:0]`、`key_gain[127:0]`和`controls_valid`；CH0位于最低16位，其余七路恒零。
- `adc_spi.v`：新版单次MCP3208读取，50MHz主时钟、500kHz Mode0、24拍、CH0命令060000，通道启动锁存及CS高保护。原labs固定CH0驱动保留作历史实验，不要重复定义/混用版本。
- `pressure_ch0_input.v`：真实CH0完整封装，依赖上面两个模块；每50,000拍请求一次，忙时跳过并输出一拍`missed_tick`。输入clk/rst_n/miso，输出cs_n/sclk/mosi及三个正式控制端口，另有raw_data/raw_valid观察口。无引脚约束，顶层统一复位同步释放。

真实接入示例（内部总线须在总top声明，参数后续按实测校准）：

```verilog
pressure_ch0_input input_controls (
    .clk(clk), .rst_n(rst_n), .miso(adc_miso),
    .cs_n(adc_cs_n), .sclk(adc_sclk), .mosi(adc_mosi),
    .gate(gate), .key_gain(key_gain), .controls_valid(controls_valid),
    .raw_data(raw_data), .raw_valid(raw_valid), .missed_tick(missed_tick)
);
```

假控制：`examples/input/fake_ch0_controls.v`，无ADC依赖；每1ms一帧，默认每1000帧切换静音→gate=1/gain=16'h4000→gate=1/gain=16'hC000→松开，再循环。复位全部为零。它与真实封装只能择一驱动同一控制总线。`examples/input/control_frame_receiver.v`演示整体锁存和sample_ce同沿读取旧帧，不是合成核心；已有接收逻辑时不用重复实例化。

参数为开发占位值：TON=256、TOFF=128、RAW_MIN=128、RAW_MAX=3840、MIN_GAIN=4096。连续两份有效样本确认按下(raw>=TON)/松开(raw<=TOFF)，滞回区保持状态。目标映射在端点处限幅，中间使用整数比例；内部Q16.8按旧值+(目标−旧值)/4平滑，首次按下从最小增益开始，按住增益不低于MIN_GAIN。松开gate/gain归零，核心应冻结此前力度完成Release。

真实路径复位静音；每1ms输入一份时输出一拍20ns的controls_valid，数据一起更新并保持到下次发布。压力模块在接受raw_valid沿后发布，消费者下一沿接收。接收端controls_valid与sample_ce同沿时本次用旧控制、下次用新控制。无raw_valid则保持最后数据、不发布新帧；不是ADC断线检测。

默认压力处理仿真22,437拍PASS；真实封装外部SPI模型闭环9帧PASS，检查1ms、24拍/060000命令、两轮确认、力度变化、松开及复位；假控制发生器仿真PASS。见[tb/input](../../tb/input/README.md)。未完成：真实12位码校准、Gowin综合/PnR/时序和该封装上板；现有八档灯成功不能升级为这些项通过。其它参数组合未验收。本次不修改A维护的最终工程、约束、音频或队长核心。

放 MCP3208 SPI、八通道扫描、逐键校准/平滑、滞回识别和功能键模块。输出 gate[7:0]、key_gain[127:0]、controls_valid、button_events[2:0]，从一键阶段使用八键端口。

完整扫描后整组交接，不交半组数据。先假ADC仿真，再已知电压和一/四/八片真实验证。见[接口](../../docs/接口约定.md)和[任务](../../docs/三人分工与交付计划.md)。
