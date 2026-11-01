`timescale 1ns/1ps
`default_nettype none
// Read-only tap on 48,828.125 Hz audio; 127-tap Q15 lowpass then /8.
// Three clocks per FIR tap; completes before the next 1024-clock audio sample.
module spectrum_decimator(
 input wire clk,rst_n,sample_valid,
 input wire signed [15:0] sample_data,
 output reg signed [15:0] filtered_data,
 output reg filtered_valid,
 output reg overrun
);
 reg signed [15:0] coeff[0:126];
 reg signed [15:0] history[0:127];
 initial $readmemh("tables/spectrum_fir127.hex",coeff);
 reg [6:0] write_ptr,base,tap;
 reg [7:0] filled;
 reg [2:0] dec_phase,state;
 reg signed [15:0] a,b;
 reg signed [31:0] product;
 reg signed [39:0] accumulator;
 wire [6:0] address=base-tap;
 wire signed [39:0] extended_product={{8{product[31]}},product};
 wire signed [39:0] scaled=accumulator>>>15;
 localparam IDLE=0,READ=1,MULT=2,ADD=3,FINISH=4;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   write_ptr<=0;base<=0;tap<=0;filled<=0;dec_phase<=0;state<=IDLE;
   a<=0;b<=0;product<=0;accumulator<=0;filtered_data<=0;filtered_valid<=0;overrun<=0;
  end else begin
   filtered_valid<=0;
   if(sample_valid) begin
    history[write_ptr]<=sample_data;
    write_ptr<=write_ptr+1'b1;
    if(filled<128) filled<=filled+1'b1;
    dec_phase<=dec_phase+1'b1;
    if(state!=IDLE) overrun<=1;
    if(dec_phase==7 && state==IDLE) begin
     base<=write_ptr;tap<=0;accumulator<=0;state<=READ;
    end
   end
   case(state)
    READ: begin a<=(tap<filled)?history[address]:16'sd0;b<=coeff[tap];state<=MULT;end
    MULT: begin product<=a*b;state<=ADD;end
    ADD: begin
     accumulator<=accumulator+extended_product;
     if(tap==126) state<=FINISH;
     else begin tap<=tap+1'b1;state<=READ;end
    end
    FINISH: begin
     if(scaled>32767) filtered_data<=16'sd32767;
     else if(scaled< -32768) filtered_data<= -16'sd32768;
     else filtered_data<=scaled[15:0];
     filtered_valid<=1;state<=IDLE;
    end
    default: ;
   endcase
  end
 end
endmodule
`default_nettype wire
