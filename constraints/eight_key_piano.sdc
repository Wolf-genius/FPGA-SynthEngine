# Initial internal clock requirement. Not full external timing sign-off.
create_clock -name clk -period 20.000 [get_ports {clk}]
# Review ADC input, SPI/audio outputs, reset and synchronization before P&R.
# All internal logic uses clk; adc_sclk and bclk are output signals.
