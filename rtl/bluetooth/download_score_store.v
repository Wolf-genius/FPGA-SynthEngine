`timescale 1ns/1ps
`default_nettype none
// A committed 256-record song RAM. No audio sequencer and no PLAY command.
// Only a successful END exposes memory to the tutorial. RAM itself is not reset.
module download_score_store(
 input wire clk,rst_n,cmd_valid,
 input wire [3:0] cmd,
 input wire [8:0] count,
 input wire [47:0] record,
 input wire crc_present,
 input wire [15:0] crc_value,
 input wire teach_active,teach_done,teach_fault,
 input wire [7:0] lesson_addr,
 output reg loading,song_valid,
 output reg vibrato_enable,
 output reg [8:0] song_count,
 output reg teach_start,
 output wire teach_stop,
 output wire step_ready,step_valid,step_last,
 output wire [7:0] step_mask,
 output wire [15:0] step_duration_ms,
 output reg reply_valid,
 output reg [4:0] reply_code,
 output reg [15:0] running_crc
);
 reg [47:0] memory[0:255];
 reg [47:0] read_data,crc_shift;
 reg [7:0] read_addr_q;
 reg read_valid_q;
 reg [8:0] expected_count,written;
 reg bad_upload,done_pending,done_seen;
 reg [5:0] crc_bits;
 wire crc_busy=crc_bits!=0;
 wire locked=teach_active || teach_start;
 wire write_event=cmd_valid && cmd==3 && loading && !locked && !bad_upload &&
                  written<expected_count && !crc_busy;
 assign teach_stop=cmd_valid && cmd==6;
 // Read data and address tag advance together. LOAD may sample only a matching tag.
 always @(posedge clk) begin
  read_data<=memory[lesson_addr];
  if(write_event)memory[written[7:0]]<=record;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin read_addr_q<=0;read_valid_q<=0;end
  else begin read_addr_q<=lesson_addr;read_valid_q<=song_valid;end
 end
 assign step_ready=read_valid_q && read_addr_q==lesson_addr;
 assign step_valid=song_valid && ({1'b0,read_addr_q}<song_count) &&
                   read_data[39:24]!=0 && read_data[23:8]<=read_data[39:24] && read_data[7:0]<=127;
 wire sounded=(read_data[47:40]!=0)&&(read_data[23:8]!=0)&&(read_data[7:0]!=0);
 assign step_mask=sounded?read_data[47:40]:8'd0;
 assign step_duration_ms=sounded?read_data[23:8]:read_data[39:24];
 assign step_last=({1'b0,read_addr_q}+9'd1)==song_count;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   loading<=0;song_valid<=0;song_count<=0;teach_start<=0;vibrato_enable<=0;
   expected_count<=0;written<=0;bad_upload<=0;crc_bits<=0;crc_shift<=0;
   running_crc<=16'hffff;reply_valid<=0;reply_code<=0;
   done_pending<=0;done_seen<=0;
  end else begin
   teach_start<=0;reply_valid<=0;done_seen<=teach_done;
   // A completion sampled during the registered restart belongs to the old run.
   if(teach_done && !done_seen && !teach_start)done_pending<=1;
   if(crc_busy)begin
    running_crc<=(running_crc<<1)^((running_crc[15]^crc_shift[47])?16'h1021:16'd0);
    crc_shift<=crc_shift<<1;crc_bits<=crc_bits-1'b1;
   end
   if(write_event)begin crc_shift<=record;crc_bits<=48;end
   if(!cmd_valid && done_pending)begin reply_valid<=1;reply_code<=15;done_pending<=0;end
   if(cmd_valid)begin
    reply_valid<=1;
    case(cmd)
     1:reply_code<=1; // PONG
     2:begin
      if(!locked && !crc_busy)begin
       expected_count<=count;written<=0;loading<=1;song_valid<=0;song_count<=0;
       bad_upload<=0;running_crc<=16'hffff;crc_bits<=0;done_pending<=0;reply_code<=2;
      end else reply_code<=12;
     end
     3:begin
      if(write_event)begin written<=written+1'b1;reply_code<=3;end
      else begin reply_code<=loading?13:12;if(loading)bad_upload<=1;end
     end
     4:begin
      if(!loading || crc_busy || locked)reply_code<=12;
      else begin
       loading<=0;song_valid<=0;
       if(bad_upload || written!=expected_count)reply_code<=13;
       else if(crc_present && running_crc!=crc_value)reply_code<=16;
       else begin song_valid<=1;song_count<=written;reply_code<=4;end
      end
     end
     6:begin // STOP: preserve a committed song, cancel an unfinished upload.
      if(loading)begin loading<=0;song_valid<=0;song_count<=0;end
      crc_bits<=0;done_pending<=0;reply_code<=6;
     end
     7:reply_code<=teach_active?21:loading?8:teach_fault?12:song_valid?9:7;
     10:begin
      if(song_valid && !loading && !crc_busy)begin
       teach_start<=1;done_pending<=0;reply_code<=18;
      end else reply_code<=12;
     end
     11:begin vibrato_enable<=1;reply_code<=23;end
     12:begin vibrato_enable<=0;reply_code<=24;end
     13:reply_code<=vibrato_enable?25:26;
     default:begin
      reply_code<=(cmd==9)?14:11;
      if(loading)begin bad_upload<=1;song_valid<=0;end
     end
    endcase
   end
  end
 end
endmodule
`default_nettype wire
