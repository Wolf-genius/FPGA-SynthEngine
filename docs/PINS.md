# 总工程 26 路引脚

原 16 路逐条保留，新增两路 UART 和八路 LED。唯一正式约束为 `constraints/eight_key_instrument_display.cst`。

| 端口 | 方向 | 球号 | 电平 |
|---|---|---|---|
| clk | 输入 | V22 | LVCMOS33 |
| rst_n | 输入 | AA13 | LVCMOS15，上拉 |
| adc_cs_n | 输出 | R18 | LVCMOS33 |
| adc_sclk | 输出 | T18 | LVCMOS33 |
| adc_mosi | 输出 | P16 | LVCMOS33 |
| adc_miso | 输入 | R17 | LVCMOS33 |
| bclk | 输出 | AA19 | LVCMOS33 |
| ws | 输出 | AA20 | LVCMOS33 |
| din | 输出 | AB21 | LVCMOS33 |
| lcd_sck | 输出 | C15 | LVCMOS33 |
| lcd_sda | 输出 | C14 | LVCMOS33 |
| lcd_cs_n | 输出 | A14 | LVCMOS33 |
| lcd_rs | 输出 | C13 | LVCMOS33 |
| lcd_res_n | 输出 | B13 | LVCMOS33 |
| key1_n | 输入 | AB13 | LVCMOS15，上拉 |
| key2_n | 输入 | Y12 | LVCMOS15，上拉 |
| bt_rx | 输入 | B15 | LVCMOS33，上拉 |
| bt_tx | 输出 | B16 | LVCMOS33 |
| led[0] | 输出 | A16 | LVCMOS33，高电平亮 |
| led[1] | 输出 | A15 | LVCMOS33，高电平亮 |
| led[2] | 输出 | A20 | LVCMOS33，高电平亮 |
| led[3] | 输出 | B20 | LVCMOS33，高电平亮 |
| led[4] | 输出 | A21 | LVCMOS33，高电平亮 |
| led[5] | 输出 | B21 | LVCMOS33，高电平亮 |
| led[6] | 输出 | B18 | LVCMOS33，高电平亮 |
| led[7] | 输出 | B17 | LVCMOS33，高电平亮 |

UART 与 LED 来自本次交付的约束及接入表；实际板卡 Bank 供电与接线由实验室核对。屏幕 SDA 是 SPI 数据线。蓝牙 TXD 接 FPGA 的 bt_rx，蓝牙 RXD 接 FPGA 的 bt_tx。

50MHz 时钟约束和 UART 第一级同步寄存器的异步输入例外在 `constraints/eight_key_full.sdc`。该文件沿用原内部时钟要求；外部接口完整时序签核仍需高云和实物验证。
