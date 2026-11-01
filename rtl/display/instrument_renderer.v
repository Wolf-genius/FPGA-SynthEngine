`timescale 1ns/1ps
`default_nettype none
// 128x160 RGB565 streaming renderer, no frame buffer and no CPU.
// 5x7 glyphs at 2x scale. Entire frame uses a stable observer snapshot.
module instrument_renderer(
 input wire [6:0] x,
 input wire [7:0] y,
 input wire [7:0] held,
 input wire [6:0] percent,
 input wire [31:0] pressure_text,
 input wire [3:0] sound_count,
 input wire [2:0] last_note,last_state,
 input wire last_valid,timbre_select,
 input wire [1:0] octave_select,
 output reg [15:0] rgb
);
 localparam [15:0] GOLD=16'hffe8, DIM=16'h52aa, BG=16'h0000;
 // Explicit constant glyph rows avoid synthesis-dependent nested ROM indexing.
 function [4:0] glyph_row;
  input [6:0] code;
  input [2:0] row;
  begin case({code,row})
   10'd520: glyph_row=5'b01110;
   10'd521: glyph_row=5'b10001;
   10'd522: glyph_row=5'b10001;
   10'd523: glyph_row=5'b11111;
   10'd524: glyph_row=5'b10001;
   10'd525: glyph_row=5'b10001;
   10'd526: glyph_row=5'b10001;
   10'd528: glyph_row=5'b11110;
   10'd529: glyph_row=5'b10001;
   10'd530: glyph_row=5'b10001;
   10'd531: glyph_row=5'b11110;
   10'd532: glyph_row=5'b10001;
   10'd533: glyph_row=5'b10001;
   10'd534: glyph_row=5'b11110;
   10'd536: glyph_row=5'b01111;
   10'd537: glyph_row=5'b10000;
   10'd538: glyph_row=5'b10000;
   10'd539: glyph_row=5'b10000;
   10'd540: glyph_row=5'b10000;
   10'd541: glyph_row=5'b10000;
   10'd542: glyph_row=5'b01111;
   10'd544: glyph_row=5'b11110;
   10'd545: glyph_row=5'b10001;
   10'd546: glyph_row=5'b10001;
   10'd547: glyph_row=5'b10001;
   10'd548: glyph_row=5'b10001;
   10'd549: glyph_row=5'b10001;
   10'd550: glyph_row=5'b11110;
   10'd552: glyph_row=5'b11111;
   10'd553: glyph_row=5'b10000;
   10'd554: glyph_row=5'b10000;
   10'd555: glyph_row=5'b11110;
   10'd556: glyph_row=5'b10000;
   10'd557: glyph_row=5'b10000;
   10'd558: glyph_row=5'b11111;
   10'd560: glyph_row=5'b11111;
   10'd561: glyph_row=5'b10000;
   10'd562: glyph_row=5'b10000;
   10'd563: glyph_row=5'b11110;
   10'd564: glyph_row=5'b10000;
   10'd565: glyph_row=5'b10000;
   10'd566: glyph_row=5'b10000;
   10'd568: glyph_row=5'b01111;
   10'd569: glyph_row=5'b10000;
   10'd570: glyph_row=5'b10000;
   10'd571: glyph_row=5'b10111;
   10'd572: glyph_row=5'b10001;
   10'd573: glyph_row=5'b10001;
   10'd574: glyph_row=5'b01111;
   10'd576: glyph_row=5'b10001;
   10'd577: glyph_row=5'b10001;
   10'd578: glyph_row=5'b10001;
   10'd579: glyph_row=5'b11111;
   10'd580: glyph_row=5'b10001;
   10'd581: glyph_row=5'b10001;
   10'd582: glyph_row=5'b10001;
   10'd584: glyph_row=5'b11111;
   10'd585: glyph_row=5'b00100;
   10'd586: glyph_row=5'b00100;
   10'd587: glyph_row=5'b00100;
   10'd588: glyph_row=5'b00100;
   10'd589: glyph_row=5'b00100;
   10'd590: glyph_row=5'b11111;
   10'd600: glyph_row=5'b10001;
   10'd601: glyph_row=5'b10010;
   10'd602: glyph_row=5'b10100;
   10'd603: glyph_row=5'b11000;
   10'd604: glyph_row=5'b10100;
   10'd605: glyph_row=5'b10010;
   10'd606: glyph_row=5'b10001;
   10'd608: glyph_row=5'b10000;
   10'd609: glyph_row=5'b10000;
   10'd610: glyph_row=5'b10000;
   10'd611: glyph_row=5'b10000;
   10'd612: glyph_row=5'b10000;
   10'd613: glyph_row=5'b10000;
   10'd614: glyph_row=5'b11111;
   10'd624: glyph_row=5'b10001;
   10'd625: glyph_row=5'b11001;
   10'd626: glyph_row=5'b11001;
   10'd627: glyph_row=5'b10101;
   10'd628: glyph_row=5'b10011;
   10'd629: glyph_row=5'b10011;
   10'd630: glyph_row=5'b10001;
   10'd632: glyph_row=5'b01110;
   10'd633: glyph_row=5'b10001;
   10'd634: glyph_row=5'b10001;
   10'd635: glyph_row=5'b10001;
   10'd636: glyph_row=5'b10001;
   10'd637: glyph_row=5'b10001;
   10'd638: glyph_row=5'b01110;
   10'd640: glyph_row=5'b11110;
   10'd641: glyph_row=5'b10001;
   10'd642: glyph_row=5'b10001;
   10'd643: glyph_row=5'b11110;
   10'd644: glyph_row=5'b10000;
   10'd645: glyph_row=5'b10000;
   10'd646: glyph_row=5'b10000;
   10'd656: glyph_row=5'b11110;
   10'd657: glyph_row=5'b10001;
   10'd658: glyph_row=5'b10001;
   10'd659: glyph_row=5'b11110;
   10'd660: glyph_row=5'b10100;
   10'd661: glyph_row=5'b10010;
   10'd662: glyph_row=5'b10001;
   10'd664: glyph_row=5'b01111;
   10'd665: glyph_row=5'b10000;
   10'd666: glyph_row=5'b10000;
   10'd667: glyph_row=5'b01110;
   10'd668: glyph_row=5'b00001;
   10'd669: glyph_row=5'b00001;
   10'd670: glyph_row=5'b11110;
   10'd672: glyph_row=5'b11111;
   10'd673: glyph_row=5'b00100;
   10'd674: glyph_row=5'b00100;
   10'd675: glyph_row=5'b00100;
   10'd676: glyph_row=5'b00100;
   10'd677: glyph_row=5'b00100;
   10'd678: glyph_row=5'b00100;
   10'd680: glyph_row=5'b10001;
   10'd681: glyph_row=5'b10001;
   10'd682: glyph_row=5'b10001;
   10'd683: glyph_row=5'b10001;
   10'd684: glyph_row=5'b10001;
   10'd685: glyph_row=5'b10001;
   10'd686: glyph_row=5'b01110;
   10'd712: glyph_row=5'b10001;
   10'd713: glyph_row=5'b10001;
   10'd714: glyph_row=5'b01010;
   10'd715: glyph_row=5'b00100;
   10'd716: glyph_row=5'b00100;
   10'd717: glyph_row=5'b00100;
   10'd718: glyph_row=5'b00100;
   10'd384: glyph_row=5'b01110;
   10'd385: glyph_row=5'b10001;
   10'd386: glyph_row=5'b10011;
   10'd387: glyph_row=5'b10101;
   10'd388: glyph_row=5'b11001;
   10'd389: glyph_row=5'b10001;
   10'd390: glyph_row=5'b01110;
   10'd392: glyph_row=5'b00100;
   10'd393: glyph_row=5'b01100;
   10'd394: glyph_row=5'b00100;
   10'd395: glyph_row=5'b00100;
   10'd396: glyph_row=5'b00100;
   10'd397: glyph_row=5'b00100;
   10'd398: glyph_row=5'b01110;
   10'd400: glyph_row=5'b01110;
   10'd401: glyph_row=5'b10001;
   10'd402: glyph_row=5'b00001;
   10'd403: glyph_row=5'b00010;
   10'd404: glyph_row=5'b00100;
   10'd405: glyph_row=5'b01000;
   10'd406: glyph_row=5'b11111;
   10'd408: glyph_row=5'b11110;
   10'd409: glyph_row=5'b00001;
   10'd410: glyph_row=5'b00001;
   10'd411: glyph_row=5'b01110;
   10'd412: glyph_row=5'b00001;
   10'd413: glyph_row=5'b00001;
   10'd414: glyph_row=5'b11110;
   10'd416: glyph_row=5'b00010;
   10'd417: glyph_row=5'b00110;
   10'd418: glyph_row=5'b01010;
   10'd419: glyph_row=5'b10010;
   10'd420: glyph_row=5'b11111;
   10'd421: glyph_row=5'b00010;
   10'd422: glyph_row=5'b00010;
   10'd424: glyph_row=5'b11111;
   10'd425: glyph_row=5'b10000;
   10'd426: glyph_row=5'b10000;
   10'd427: glyph_row=5'b11110;
   10'd428: glyph_row=5'b00001;
   10'd429: glyph_row=5'b00001;
   10'd430: glyph_row=5'b11110;
   10'd432: glyph_row=5'b01110;
   10'd433: glyph_row=5'b10000;
   10'd434: glyph_row=5'b10000;
   10'd435: glyph_row=5'b11110;
   10'd436: glyph_row=5'b10001;
   10'd437: glyph_row=5'b10001;
   10'd438: glyph_row=5'b01110;
   10'd440: glyph_row=5'b11111;
   10'd441: glyph_row=5'b00001;
   10'd442: glyph_row=5'b00010;
   10'd443: glyph_row=5'b00100;
   10'd444: glyph_row=5'b01000;
   10'd445: glyph_row=5'b01000;
   10'd446: glyph_row=5'b01000;
   10'd448: glyph_row=5'b01110;
   10'd449: glyph_row=5'b10001;
   10'd450: glyph_row=5'b10001;
   10'd451: glyph_row=5'b01110;
   10'd452: glyph_row=5'b10001;
   10'd453: glyph_row=5'b10001;
   10'd454: glyph_row=5'b01110;
   10'd456: glyph_row=5'b01110;
   10'd457: glyph_row=5'b10001;
   10'd458: glyph_row=5'b10001;
   10'd459: glyph_row=5'b01111;
   10'd460: glyph_row=5'b00001;
   10'd461: glyph_row=5'b00001;
   10'd462: glyph_row=5'b01110;
   10'd465: glyph_row=5'b00100;
   10'd466: glyph_row=5'b00100;
   10'd468: glyph_row=5'b00100;
   10'd469: glyph_row=5'b00100;
   10'd376: glyph_row=5'b00001;
   10'd377: glyph_row=5'b00001;
   10'd378: glyph_row=5'b00010;
   10'd379: glyph_row=5'b00100;
   10'd380: glyph_row=5'b01000;
   10'd381: glyph_row=5'b10000;
   10'd382: glyph_row=5'b10000;
   10'd296: glyph_row=5'b11001;
   10'd297: glyph_row=5'b11010;
   10'd298: glyph_row=5'b00100;
   10'd299: glyph_row=5'b01000;
   10'd300: glyph_row=5'b10110;
   10'd301: glyph_row=5'b00110;
   default: glyph_row=5'b00000;
  endcase end
 endfunction
 function [7:0] note_letter;
  input [2:0] note;
  begin case(note)
   0:note_letter="C"; 1:note_letter="D"; 2:note_letter="E";
   3:note_letter="F"; 4:note_letter="G"; 5:note_letter="A";
   6:note_letter="B"; default:note_letter="C";
  endcase end
 endfunction
 function [79:0] phase_text;
  input [2:0] state;
  begin case(state)
   1:phase_text="ATTACK    ";
   2:phase_text="DECAY     ";
   3:phase_text="HOLD      ";
   4:phase_text="RELEASE   ";
   default:phase_text="OFF       ";
  endcase end
 endfunction
 function [7:0] octave_digit;
  input [2:0] note;
  input [1:0] octave;
  reg [7:0] base;
  begin
   base=(note==7)?8'h35:8'h34;
   octave_digit=(octave==1)?base+8'd1:(octave==2)?base-8'd1:base;
  end
 endfunction
 reg [79:0] line;
 reg [7:0] character;
 reg [2:0] glyph_x,glyph_y,key;
 reg [3:0] column;
 reg text_on;
 reg [15:0] foreground;
 reg [4:0] glyph_bits;
 reg ink;
 reg [7:0] local_y;
 reg [7:0] bar_end;
 reg [79:0] phase_line;
 integer c;
 always @* begin
  rgb=BG; line="          "; text_on=0; character=" ";
  glyph_x=0; glyph_y=0; column=0; foreground=GOLD;
  local_y=0; key=0; phase_line=phase_text(last_state);
  // Interior bar has exactly 100 columns, one per percentage point.
  bar_end=8'd14+{1'b0,percent};
  if(y>=123 && y<=134 && x>=12 && x<=115) begin
   if(y==123 || y==134 || x==12 || x==115) rgb=GOLD;
   else if(x>=14 && x<bar_end) rgb=GOLD;
   else rgb=16'h2104;
  end
  if(y>=4 && y<18) begin line=timbre_select ? {"GUITAR  C",octave_digit(0,octave_select)} : {"PIANO   C",octave_digit(0,octave_select)}; local_y=y-4; text_on=1; end
  else if(y>=22 && y<36) begin line="HELD:     "; local_y=y-22; text_on=1; end
  else if(y>=82 && y<96) begin
   line={"SOUND:",(8'h30+{4'b0,sound_count}),"/8 "}; local_y=y-82; text_on=1;
  end else if(y>=103 && y<117) begin
   line={"PRESS:",pressure_text};
   local_y=y-103; text_on=1;
  end else if(y>=143 && y<157) begin
   if(last_valid) line={note_letter(last_note),octave_digit(last_note,octave_select),8'h3a,phase_line[79:24]};
   else line="READY     ";
   local_y=y-143; text_on=1;
  end
  if(text_on) begin
   text_on=0;
   for(c=0;c<10;c=c+1) if(x>=4+c*12 && x<14+c*12) begin
    column=c; glyph_x=(x-4-c*12)>>1; text_on=1;
   end
   glyph_y=local_y[3:1];
   character=(line >> ((9-column)*8));
  end
  // Eight large note boxes, same C4..C5 order as the real note table.
  if((y>=36 && y<=53)||(y>=58 && y<=75)) begin
   key={(y>=58),x[6:5]};
   local_y=(y>=58)?y-58:y-36;
   if(x[4:0]>=2 && x[4:0]<=29) begin
    rgb=held[key]?GOLD:BG;
    if(x[4:0]==2 || x[4:0]==29 || local_y==0 || local_y==17) rgb=held[key]?GOLD:DIM;
    if(local_y>=2 && local_y<16) begin
     glyph_y=(local_y-2)>>1;
     if(x[4:0]>=4 && x[4:0]<14) begin
      character=note_letter(key); glyph_x=(x[4:0]-4)>>1; text_on=1;
     end else if(x[4:0]>=16 && x[4:0]<26) begin
      character=octave_digit(key,octave_select); glyph_x=(x[4:0]-16)>>1; text_on=1;
     end
    end
    foreground=held[key]?BG:DIM;
   end
  end
  glyph_bits=glyph_row(character[6:0],glyph_y);
  case(glyph_x)
   0:ink=glyph_bits[4]; 1:ink=glyph_bits[3]; 2:ink=glyph_bits[2];
   3:ink=glyph_bits[1]; 4:ink=glyph_bits[0]; default:ink=0;
  endcase
  if(text_on && ink) rgb=foreground;
 end
endmodule
`default_nettype wire
