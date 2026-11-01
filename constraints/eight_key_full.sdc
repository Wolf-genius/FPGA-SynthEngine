# Initial internal clock requirement. Not full external timing sign-off.
create_clock -name clk -period 20.000 [get_ports {clk}]
# Review ADC input, SPI/audio outputs, reset and synchronization before P&R.
# All internal logic uses clk; adc_sclk and bclk are output signals.

# JDY-31 RX is asynchronous; exempt only the first synchronizer register.
set_false_path -from [get_ports {bt_rx}] -to [get_cells {*rx_meta*}]
