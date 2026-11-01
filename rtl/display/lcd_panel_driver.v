`timescale 1ns/1ps
`default_nettype none
module lcd_panel_driver #(
 parameter integer SPI_HALF_CYCLES=5,
 parameter integer RESET_LOW_CYCLES=5000000,
 parameter integer RESET_HIGH_CYCLES=2500000,
 parameter integer SLEEP_OUT_CYCLES=6000000,
 parameter integer PAGE_HOLD_CYCLES=500000,
 parameter [7:0] X_OFFSET=0,Y_OFFSET=0,
 parameter [7:0] MADCTL=8'hc0
)(
 input wire clk,rst_n,
 output wire lcd_sck,lcd_sda,lcd_cs_n,lcd_rs,
 output reg lcd_res_n,
 input wire [15:0] pixel_rgb,
 output reg [6:0] x,
 output reg [7:0] y,
 output reg frame_start
);
 reg start,mode;
 reg [7:0] tx_data;
 wire busy,done;
 spi_byte_tx #(.HALF_CYCLES(SPI_HALF_CYCLES)) spi(
  .clk(clk),.rst_n(rst_n),.start(start),.data(tx_data),.data_mode(mode),
  .busy(busy),.done(done),.cs_n(lcd_cs_n),.sclk(lcd_sck),.mosi(lcd_sda),.dc(lcd_rs));
 // Initialization from the supplied vendor's Lcd_Driver.c.
 // Sleep-out (11) and its 120 ms wait are handled separately.
 function [8:0] init_byte;
  input [7:0] index;
  begin
   case(index)
    8'd0: init_byte=9'h0b1;
    8'd1: init_byte=9'h101;
    8'd2: init_byte=9'h12c;
    8'd3: init_byte=9'h12d;
    8'd4: init_byte=9'h0b2;
    8'd5: init_byte=9'h101;
    8'd6: init_byte=9'h12c;
    8'd7: init_byte=9'h12d;
    8'd8: init_byte=9'h0b3;
    8'd9: init_byte=9'h101;
    8'd10: init_byte=9'h12c;
    8'd11: init_byte=9'h12d;
    8'd12: init_byte=9'h101;
    8'd13: init_byte=9'h12c;
    8'd14: init_byte=9'h12d;
    8'd15: init_byte=9'h0b4;
    8'd16: init_byte=9'h107;
    8'd17: init_byte=9'h0c0;
    8'd18: init_byte=9'h1a2;
    8'd19: init_byte=9'h102;
    8'd20: init_byte=9'h184;
    8'd21: init_byte=9'h0c1;
    8'd22: init_byte=9'h1c5;
    8'd23: init_byte=9'h0c2;
    8'd24: init_byte=9'h10a;
    8'd25: init_byte=9'h100;
    8'd26: init_byte=9'h0c3;
    8'd27: init_byte=9'h18a;
    8'd28: init_byte=9'h12a;
    8'd29: init_byte=9'h0c4;
    8'd30: init_byte=9'h18a;
    8'd31: init_byte=9'h1ee;
    8'd32: init_byte=9'h0c5;
    8'd33: init_byte=9'h10e;
    8'd34: init_byte=9'h036;
    8'd35: init_byte=9'h1c0;
    8'd36: init_byte=9'h0e0;
    8'd37: init_byte=9'h10f;
    8'd38: init_byte=9'h11a;
    8'd39: init_byte=9'h10f;
    8'd40: init_byte=9'h118;
    8'd41: init_byte=9'h12f;
    8'd42: init_byte=9'h128;
    8'd43: init_byte=9'h120;
    8'd44: init_byte=9'h122;
    8'd45: init_byte=9'h11f;
    8'd46: init_byte=9'h11b;
    8'd47: init_byte=9'h123;
    8'd48: init_byte=9'h137;
    8'd49: init_byte=9'h100;
    8'd50: init_byte=9'h107;
    8'd51: init_byte=9'h102;
    8'd52: init_byte=9'h110;
    8'd53: init_byte=9'h0e1;
    8'd54: init_byte=9'h10f;
    8'd55: init_byte=9'h11b;
    8'd56: init_byte=9'h10f;
    8'd57: init_byte=9'h117;
    8'd58: init_byte=9'h133;
    8'd59: init_byte=9'h12c;
    8'd60: init_byte=9'h129;
    8'd61: init_byte=9'h12e;
    8'd62: init_byte=9'h130;
    8'd63: init_byte=9'h130;
    8'd64: init_byte=9'h139;
    8'd65: init_byte=9'h13f;
    8'd66: init_byte=9'h100;
    8'd67: init_byte=9'h107;
    8'd68: init_byte=9'h103;
    8'd69: init_byte=9'h110;
    8'd70: init_byte=9'h02a;
    8'd71: init_byte=9'h100;
    8'd72: init_byte=9'h100;
    8'd73: init_byte=9'h100;
    8'd74: init_byte=9'h17f;
    8'd75: init_byte=9'h02b;
    8'd76: init_byte=9'h100;
    8'd77: init_byte=9'h100;
    8'd78: init_byte=9'h100;
    8'd79: init_byte=9'h19f;
    8'd80: init_byte=9'h0f0;
    8'd81: init_byte=9'h101;
    8'd82: init_byte=9'h0f6;
    8'd83: init_byte=9'h100;
    8'd84: init_byte=9'h03a;
    8'd85: init_byte=9'h105;
    8'd86: init_byte=9'h029;
    default: init_byte=9'h029;
   endcase
  end
 endfunction
 localparam integer INIT_COUNT=87;

 localparam RESET_LOW=0,RESET_HIGH=1,SLEEP_CMD=2,SLEEP_WAIT=3,
            INIT=4,HEADER=5,PIXEL_HI=6,PIXEL_LO=7,PIXEL_NEXT=8,
            PAGE_WAIT=9,WAIT_TX=10;
 reg [3:0] state,resume_state;
 reg [31:0] timer;
 reg [7:0] init_index;
 reg [3:0] header_index;

 wire [7:0] x_end=8'd127+X_OFFSET;
 wire [7:0] y_end=8'd159+Y_OFFSET;
 reg [7:0] header_data;
 always @* begin
  case(header_index)
   0: header_data=8'h2a;
   1: header_data=0;
   2: header_data=X_OFFSET;
   3: header_data=0;
   4: header_data=x_end;
   5: header_data=8'h2b;
   6: header_data=0;
   7: header_data=Y_OFFSET;
   8: header_data=0;
   9: header_data=y_end;
   default: header_data=8'h2c;
  endcase
 end
 wire [8:0] init_word=init_byte(init_index);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   start<=0; mode<=0; tx_data<=0; lcd_res_n<=0;
   state<=RESET_LOW; resume_state<=RESET_LOW; timer<=0;
   init_index<=0; header_index<=0; x<=0; y<=0; frame_start<=0;
  end else begin
   start<=0; frame_start<=0;
   case(state)
    RESET_LOW: if(timer==RESET_LOW_CYCLES-1) begin
     timer<=0; lcd_res_n<=1; state<=RESET_HIGH;
    end else timer<=timer+1'b1;
    RESET_HIGH: if(timer==RESET_HIGH_CYCLES-1) begin
     timer<=0; state<=SLEEP_CMD;
    end else timer<=timer+1'b1;
    SLEEP_CMD: begin
     tx_data<=8'h11; mode<=0; start<=1;
     resume_state<=SLEEP_WAIT; state<=WAIT_TX;
    end
    SLEEP_WAIT: if(timer==SLEEP_OUT_CYCLES-1) begin
     timer<=0; state<=INIT;
    end else timer<=timer+1'b1;
    INIT: begin
     tx_data<=(init_word[8] && init_index==35)? MADCTL : init_word[7:0];
     mode<=init_word[8]; start<=1; state<=WAIT_TX;
     if(init_index==INIT_COUNT-1) begin header_index<=0; frame_start<=1; resume_state<=HEADER; end
     else begin init_index<=init_index+1'b1; resume_state<=INIT; end
    end
    HEADER: begin
     tx_data<=header_data;
     mode<=!(header_index==0 || header_index==5 || header_index==10);
     start<=1; state<=WAIT_TX;
     if(header_index==10) begin x<=0; y<=0; resume_state<=PIXEL_HI; end
     else begin header_index<=header_index+1'b1; resume_state<=HEADER; end
    end
    PIXEL_HI: begin
     tx_data<=pixel_rgb[15:8]; mode<=1; start<=1;
     resume_state<=PIXEL_LO; state<=WAIT_TX;
    end
    PIXEL_LO: begin
     tx_data<=pixel_rgb[7:0]; mode<=1; start<=1;
     resume_state<=PIXEL_NEXT; state<=WAIT_TX;
    end
    PIXEL_NEXT: begin
     if(x==127) begin
      x<=0;
      if(y==159) begin y<=0; timer<=0; state<=PAGE_WAIT; end
      else begin y<=y+1'b1; state<=PIXEL_HI; end
     end else begin x<=x+1'b1; state<=PIXEL_HI; end
    end
    PAGE_WAIT: if(timer==PAGE_HOLD_CYCLES-1) begin
     timer<=0; frame_start<=1;
     header_index<=0; state<=HEADER;
    end else timer<=timer+1'b1;
    WAIT_TX: if(done) state<=resume_state;
    default: state<=RESET_LOW;
   endcase
  end
 end
endmodule
`default_nettype wire
