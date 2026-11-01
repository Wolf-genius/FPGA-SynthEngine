`timescale 1ns/1ps
`default_nettype none
// Queue complete response IDs, never partial strings. Normal NOTE upload has
// fewer reply bytes than input bytes. A command flood raises a sticky flag and
// emits ERR TXFULL once space returns; it cannot corrupt the score memory.
module score_reply_uart #(parameter integer CLKS_PER_BIT=5208)(
 input wire clk,rst_n,reply_valid,
 input wire [4:0] reply_code,
 output wire tx,
 output reg overflow_seen
);
 reg [4:0] fifo[0:15];
 reg [3:0] wr,rd,index;
 reg [4:0] count,active;
 reg [2:0] state;
 reg pending_overflow,start;
 reg [7:0] rom[0:511],character;
 wire busy;
 wire pop=state==0 && count!=0;
 wire room=count<16 || pop;
 wire inject=!reply_valid && pending_overflow && room;
 wire push=(reply_valid&&room)||inject;
 reg [4:0] length;
 initial $readmemh("tables/replies.hex",rom);
 always @* begin
  case(active)
   1:length=6;2:length=10;3:length=9;4:length=8;5:length=9;6:length=9;
   7:length=14;8:length=16;9:length=14;10:length=16;
   11:length=12;12:length=11;13:length=11;14:length=11;
   15:length=6;16:length=9;17:length=12;
   18:length=10;19:length=12;20:length=9;21:length=14;22:length=16;
   23:length=10;24:length=11;25:length=12;26:length=13;
   default:length=0;
  endcase
 end
 always @(posedge clk) character<=rom[{active,index}];
 uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) sender(.clk(clk),.rst_n(rst_n),
  .start(start),.data(character),.tx(tx),.busy(busy));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   wr<=0;rd<=0;index<=0;count<=0;active<=0;state<=0;
   start<=0;overflow_seen<=0;pending_overflow<=0;
  end else begin
   start<=0;
   if(push) begin fifo[wr]<=inject?5'd17:reply_code;wr<=wr+1'b1;end
   if(pop) begin active<=fifo[rd];rd<=rd+1'b1;index<=0;state<=1;end
   case({push,pop}) 2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
   if(inject) pending_overflow<=0;
   if(reply_valid && !room) begin overflow_seen<=1;pending_overflow<=1;end
   case(state)
    1:state<=2;
    2:state<=3;
    3:if(!busy) begin start<=1;state<=4;end
    4:if(busy) state<=5;
    5:if(!busy) begin
     if({1'b0,index}+5'd1>=length) state<=0;
     else begin index<=index+1'b1;state<=1;end
    end
    default:;
   endcase
  end
 end
endmodule
`default_nettype wire
