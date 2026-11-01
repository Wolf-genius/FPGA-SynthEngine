`timescale 1ns/1ps
`default_nettype none
// SPI mode 0, MSB first. HALF_CYCLES=10 gives 2.5 MHz at 50 MHz.
module spi_byte_tx #(parameter integer HALF_CYCLES=10)(
 input wire clk,rst_n,start,
 input wire [7:0] data,
 input wire data_mode,
 output reg busy,done,cs_n,sclk,mosi,dc
);
 reg [31:0] count;
 reg [7:0] shift;
 reg [2:0] bit_index;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   busy<=0; done<=0; cs_n<=1; sclk<=0; mosi<=0; dc<=0;
   count<=0; shift<=0; bit_index<=0;
  end else begin
   done<=0;
   if(!busy) begin
    if(start) begin
     busy<=1; cs_n<=0; sclk<=0; dc<=data_mode;
     shift<=data; mosi<=data[7]; bit_index<=7; count<=0;
    end
   end else if(count==HALF_CYCLES-1) begin
    count<=0;
    if(!sclk) sclk<=1;
    else begin
     sclk<=0;
     if(bit_index==0) begin busy<=0; done<=1; cs_n<=1; end
     else begin
      bit_index<=bit_index-1'b1;
      shift<={shift[6:0],1'b0}; mosi<=shift[6];
     end
    end
   end else count<=count+1'b1;
  end
 end
endmodule
`default_nettype wire
