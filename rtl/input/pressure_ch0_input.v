`timescale 1ns/1ps
`default_nettype none
// Real CH0 integration wrapper. Board top owns pins and synchronized reset release.
module pressure_ch0_input #(
    parameter integer SAMPLE_CYCLES=50000,
    parameter [11:0] TON=12'd256, TOFF=12'd128,
    parameter [11:0] RAW_MIN=12'd128, RAW_MAX=12'd3840,
    parameter [15:0] MIN_GAIN=16'd4096
)(
    input wire clk, rst_n, miso,
    output wire cs_n, sclk, mosi,
    output wire [7:0] gate,
    output wire [127:0] key_gain,
    output wire controls_valid,
    output wire [11:0] raw_data,
    output wire raw_valid,
    output reg missed_tick
);
    localparam integer W=(SAMPLE_CYCLES<2)?1:$clog2(SAMPLE_CYCLES);
    reg [W-1:0] count;
    reg start;
    wire busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin count<=0; start<=0; missed_tick<=0; end
        else begin
            start<=0; missed_tick<=0;
            if(count==SAMPLE_CYCLES-1) begin
                count<=0;
                if(!busy && !start) start<=1;
                else missed_tick<=1;
            end else count<=count+1'b1;
        end
    end
    adc_spi adc(.clk(clk),.rst_n(rst_n),.start(start),.channel(3'd0),
        .miso(miso),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),
        .busy(busy),.data(raw_data),.valid(raw_valid));
    pressure_ch0_controls #(.TON(TON),.TOFF(TOFF),.RAW_MIN(RAW_MIN),
        .RAW_MAX(RAW_MAX),.MIN_GAIN(MIN_GAIN)) controls(
        .clk(clk),.rst_n(rst_n),.raw_data(raw_data),.raw_valid(raw_valid),
        .gate(gate),.key_gain(key_gain),.controls_valid(controls_valid));
`ifndef SYNTHESIS
    initial if(SAMPLE_CYCLES<1) $fatal(1,"SAMPLE_CYCLES must be positive");
`endif
endmodule
`default_nettype wire
