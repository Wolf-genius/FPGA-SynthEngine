`timescale 1ns/1ps
`default_nettype none
// Streaming ASCII lines. No CPU, no unbounded line buffer. CR ignored, LF ends
// a command; decimal fields <=5 digits, NOTE mask 2 hex, optional END CRC 4 hex.
// Public: PING,BEGIN,NOTE,END,TEACH,STOP,STATUS. No automatic playback commands.
module score_command_parser #(parameter integer ENABLE_LESSON_COMMANDS=0,parameter integer ENABLE_VIBRATO_COMMANDS=0)(
 input wire clk,rst_n,rx_valid,rx_error,
 input wire [7:0] rx_data,
 output reg cmd_valid,
 output reg [3:0] cmd,
 output reg [8:0] count,
 output reg [47:0] record,
 output reg crc_present,
 output reg [15:0] crc_value
);
 reg [63:0] word;
 reg [3:0] word_len;
 reg [6:0] line_len;
 reg fields,bad,discard;
 reg [2:0] kind,field_index;
 reg [3:0] digits;
 reg [19:0] number;
 reg [7:0] mask;
 reg [15:0] duration,hold;
 wire hex_field=(kind==3 && field_index==0)||(kind==4 && field_index==0);
 wire decimal_ok=rx_data>="0" && rx_data<="9";
 wire hex_ok=decimal_ok || (rx_data>="A"&&rx_data<="F") || (rx_data>="a"&&rx_data<="f");
 wire [7:0] hex_digit=decimal_ok?rx_data-8'd48:
                      (rx_data>="a"?rx_data-8'd87:rx_data-8'd55);
 task clear_line;
  begin word<=0;word_len<=0;line_len<=0;fields<=0;bad<=0;discard<=0;
   kind<=0;field_index<=0;digits<=0;number<=0;mask<=0;duration<=0;hold<=0;
  end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   clear_line();cmd_valid<=0;cmd<=0;count<=0;record<=0;crc_present<=0;crc_value<=0;
  end else begin
   cmd_valid<=0;
   if(rx_error) begin
    clear_line();discard<=1;cmd<=8;cmd_valid<=1;
   end else if(rx_valid) begin
    if(rx_data==10) begin
     if(discard) clear_line();
     else begin
      if(line_len!=0) begin
       cmd_valid<=1;cmd<=8;crc_present<=0;
       if(!bad && !fields) begin
        case(word)
         "PING":cmd<=1;"END":cmd<=4;"STOP":cmd<=6;"STATUS":cmd<=7;
         "TEACH":cmd<=ENABLE_LESSON_COMMANDS ? 4'd10 : 4'd8;
         "VIBON":cmd<=ENABLE_VIBRATO_COMMANDS ? 4'd11 : 4'd8;
         "VIBOFF":cmd<=ENABLE_VIBRATO_COMMANDS ? 4'd12 : 4'd8;
         "VIBSTAT":cmd<=ENABLE_VIBRATO_COMMANDS ? 4'd13 : 4'd8;
         default:cmd<=8;
        endcase
       end else if(!bad && fields && digits!=0) begin
        if(kind==2 && field_index==0) begin
         if(number>=1 && number<=256) begin cmd<=2;count<=number[8:0];end
         else cmd<=9;
        end else if(kind==3 && field_index==3) begin
         if(duration>=1 && duration<=60000 && hold<=duration && number<=127) begin
          cmd<=3;record<={mask,duration,hold,number[7:0]};
         end else cmd<=9;
        end else if(kind==4 && field_index==0 && digits==4) begin
         cmd<=4;crc_present<=1;crc_value<=number[15:0];
        end
       end
      end
      clear_line();
     end
    end else if(rx_data!=13 && !discard) begin
     if(line_len==63) bad<=1;
     else line_len<=line_len+1'b1;
     if(!bad) begin
      if(!fields) begin
       if(rx_data==",") begin
        fields<=1;field_index<=0;digits<=0;number<=0;
        case(word) "BEGIN":kind<=2;"NOTE":kind<=3;"END":kind<=4;default:bad<=1;endcase
       end else if(word_len<8) begin word<={word[55:0],rx_data};word_len<=word_len+1'b1;end
       else bad<=1;
      end else if(rx_data==",") begin
       if(kind!=3 || digits==0 || field_index>=3) bad<=1;
       else begin
        case(field_index)
         0:if(digits==2) mask<=number[7:0];else bad<=1;
         1:if(number>=1 && number<=60000) duration<=number[15:0];else bad<=1;
         2:if(number<=60000) hold<=number[15:0];else bad<=1;
         default:bad<=1;
        endcase
        field_index<=field_index+1'b1;number<=0;digits<=0;
       end
      end else if(hex_field) begin
       if(!hex_ok || digits>=((kind==3)?2:4)) bad<=1;
       else begin number<=(number<<4)|{12'd0,hex_digit};digits<=digits+1'b1;end
      end else begin
       if(!decimal_ok || digits>=5) bad<=1;
       else begin number<=number*20'd10+{12'd0,rx_data}-20'd48;digits<=digits+1'b1;end
      end
     end
    end
   end
  end
 end
endmodule
`default_nettype wire
