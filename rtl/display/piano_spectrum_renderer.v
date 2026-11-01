`timescale 1ns/1ps
`default_nettype none
// Logical 160x128 landscape. Eight real white-note controls, five decorative
// black keys. Continuous connected spectrum contour and solid area fill.
module piano_spectrum_renderer #(
 parameter PRESELECTED_HEIGHTS=0
)(
 input wire [7:0] x,y,
 input wire [7:0] held,
 input wire [1:0] octave_select,
 input wire timbre_select,
 input wire [902:0] heights,
 input wire [6:0] height_current,height_previous,
 output reg [15:0] rgb
);
 localparam [15:0] BG=16'h10c3,GRID=16'h2126,FILL=16'h1928,
  CURVE=16'h7dba,AXIS=16'h5b4e,WHITE=16'hef5d,INK=16'h10c3,
  EDGE=16'had75,PRESSED=16'h7dba,PRESSED_EDGE=16'h5431,
  BLACK=16'h0841,BLACK_TOP=16'h2125,TEXT=16'hc638;
 localparam [15:0] GOLD=16'hfe68,GUITAR_FILL=16'h3982,
  WOOD=16'h28e2,WOOD_ACTIVE=16'h62c3,FRET=16'h8bc9,STRING=16'hb4ad;
 function [4:0] glyph;
  input [7:0] c;
  input [2:0] row;
  begin
   case({c,row})
    // C D E F G A B; numerals 0 1 3 4 5 6 and k, dot.
    11'd536:glyph=14;11'd537:glyph=17;11'd538:glyph=16;11'd539:glyph=16;11'd540:glyph=16;11'd541:glyph=17;11'd542:glyph=14;
    11'd544:glyph=30;11'd545:glyph=17;11'd546:glyph=17;11'd547:glyph=17;11'd548:glyph=17;11'd549:glyph=17;11'd550:glyph=30;
    11'd552:glyph=31;11'd553:glyph=16;11'd554:glyph=16;11'd555:glyph=30;11'd556:glyph=16;11'd557:glyph=16;11'd558:glyph=31;
    11'd560:glyph=31;11'd561:glyph=16;11'd562:glyph=16;11'd563:glyph=30;11'd564:glyph=16;11'd565:glyph=16;11'd566:glyph=16;
    11'd568:glyph=14;11'd569:glyph=17;11'd570:glyph=16;11'd571:glyph=23;11'd572:glyph=17;11'd573:glyph=17;11'd574:glyph=14;
    11'd520:glyph=14;11'd521:glyph=17;11'd522:glyph=17;11'd523:glyph=31;11'd524:glyph=17;11'd525:glyph=17;11'd526:glyph=17;
    11'd528:glyph=30;11'd529:glyph=17;11'd530:glyph=17;11'd531:glyph=30;11'd532:glyph=17;11'd533:glyph=17;11'd534:glyph=30;
    11'd384:glyph=14;11'd385:glyph=17;11'd386:glyph=19;11'd387:glyph=21;11'd388:glyph=25;11'd389:glyph=17;11'd390:glyph=14;
    11'd392:glyph=4;11'd393:glyph=12;11'd394:glyph=4;11'd395:glyph=4;11'd396:glyph=4;11'd397:glyph=4;11'd398:glyph=14;
    11'd408:glyph=30;11'd409:glyph=1;11'd410:glyph=1;11'd411:glyph=14;11'd412:glyph=1;11'd413:glyph=1;11'd414:glyph=30;
    11'd416:glyph=2;11'd417:glyph=6;11'd418:glyph=10;11'd419:glyph=18;11'd420:glyph=31;11'd421:glyph=2;11'd422:glyph=2;
    11'd424:glyph=31;11'd425:glyph=16;11'd426:glyph=16;11'd427:glyph=30;11'd428:glyph=1;11'd429:glyph=1;11'd430:glyph=30;
    11'd432:glyph=14;11'd433:glyph=16;11'd434:glyph=16;11'd435:glyph=30;11'd436:glyph=17;11'd437:glyph=17;11'd438:glyph=14;
    11'd856:glyph=16;11'd857:glyph=16;11'd858:glyph=18;11'd859:glyph=20;11'd860:glyph=24;11'd861:glyph=20;11'd862:glyph=18;
    11'd373:glyph=4;11'd374:glyph=4;
    11'd640:glyph=30;11'd641:glyph=17;11'd642:glyph=17;11'd643:glyph=30;11'd644:glyph=16;11'd645:glyph=16;11'd646:glyph=16;
    11'd584:glyph=14;11'd585:glyph=4;11'd586:glyph=4;11'd587:glyph=4;11'd588:glyph=4;11'd589:glyph=4;11'd590:glyph=14;
    11'd624:glyph=17;11'd625:glyph=25;11'd626:glyph=25;11'd627:glyph=21;11'd628:glyph=19;11'd629:glyph=19;11'd630:glyph=17;
    11'd632:glyph=14;11'd633:glyph=17;11'd634:glyph=17;11'd635:glyph=17;11'd636:glyph=17;11'd637:glyph=17;11'd638:glyph=14;
    11'd680:glyph=17;11'd681:glyph=17;11'd682:glyph=17;11'd683:glyph=17;11'd684:glyph=17;11'd685:glyph=17;11'd686:glyph=14;
    11'd672:glyph=31;11'd673:glyph=4;11'd674:glyph=4;11'd675:glyph=4;11'd676:glyph=4;11'd677:glyph=4;11'd678:glyph=4;
    11'd656:glyph=30;11'd657:glyph=17;11'd658:glyph=17;11'd659:glyph=30;11'd660:glyph=20;11'd661:glyph=18;11'd662:glyph=17;
    11'd688:glyph=17;11'd689:glyph=17;11'd690:glyph=17;11'd691:glyph=17;11'd692:glyph=17;11'd693:glyph=10;11'd694:glyph=4;
    11'd664:glyph=15;11'd665:glyph=16;11'd666:glyph=16;11'd667:glyph=14;11'd668:glyph=1;11'd669:glyph=1;11'd670:glyph=30;
    11'd960:glyph=0;11'd961:glyph=0;11'd962:glyph=17;11'd963:glyph=10;11'd964:glyph=4;11'd965:glyph=10;11'd966:glyph=17;
    default:glyph=0;
   endcase
  end
 endfunction
 function dot;
  input [4:0] row;
  input [2:0] col;
  begin case(col)
   0:dot=row[4];1:dot=row[3];2:dot=row[2];3:dot=row[1];4:dot=row[0];default:dot=0;
  endcase end
 endfunction
 // Bounded coordinate widths are important: signed 32-bit division/modulo in
 // a pixel path otherwise synthesizes a large, slow combinational network.
 reg [2:0] key,char_col,char_row;
 reg [4:0] local_x;
 wire [7:0] bin_address=x-8'd16;
 wire [7:0] previous_address=(bin_address==0)?8'd0:bin_address-1'b1;
 reg [6:0] h,hp,lo,hi;
 reg [7:0] letter,digit,ch;
 reg black_key;
 integer c;
 always @* begin
  rgb=BG;key=0;local_x=0;h=0;hp=0;lo=0;hi=0;
  char_col=0;char_row=0;letter="C";digit="4";ch=0;black_key=0;
  if(x>=16 && x<=144 && y>=8 && y<=68) begin
   if(PRESELECTED_HEIGHTS) begin h=height_current;hp=height_previous;end
   else begin h=heights[bin_address*7+:7];hp=heights[previous_address*7+:7];end
   lo=(h<hp)?h:hp;hi=(h>hp)?h:hp;
   if(x==16 || x==48 || x==80 || x==112 || x==144 || y==8 || y==28 || y==48) rgb=GRID;
   if(y>7'd68-h && y<68 && h!=0) rgb=timbre_select?GUITAR_FILL:FILL;
   if(y>=7'd68-hi && y<=7'd68-lo && hi!=0) rgb=timbre_select?GOLD:CURVE;
   if(y==68) rgb=AXIS;
  end
  if(y>=73 && y<=79) begin
   char_row=y-73;
   if(x>=14 && x<19) begin ch="0";char_col=x-14;end
   else if(x>=70 && x<75) begin ch="1";char_col=x-8'd70;end
   else if(x>=76 && x<81) begin ch=".";char_col=x-8'd76;end
   else if(x>=82 && x<87) begin ch="5";char_col=x-8'd82;end
   else if(x>=88 && x<93) begin ch="k";char_col=x-8'd88;end
   else if(x>=137 && x<142) begin ch="3";char_col=x-8'd137;end
   else if(x>=143 && x<148) begin ch="k";char_col=x-8'd143;end
   if(dot(glyph(ch,char_row[2:0]),char_col[2:0])) rgb=TEXT;
  end
  if(y>=86 && y<=127 && x<160) begin
   if(x<20) begin key=0;local_x=x[4:0];end
   else if(x<40) begin key=1;local_x=x-8'd20;end
   else if(x<60) begin key=2;local_x=x-8'd40;end
   else if(x<80) begin key=3;local_x=x-8'd60;end
   else if(x<100) begin key=4;local_x=x-8'd80;end
   else if(x<120) begin key=5;local_x=x-8'd100;end
   else if(x<140) begin key=6;local_x=x-8'd120;end
   else begin key=7;local_x=x-8'd140;end
   if(timbre_select) begin
    rgb=held[key]?WOOD_ACTIVE:WOOD;
    if(y==96 || y==105) rgb=STRING;
    if(local_x==0 || local_x==19 || y==86 || y==127) rgb=held[key]?GOLD:FRET;
    if(held[key] && y>=109 && y<=113 && local_x>=8 && local_x<=12) begin
     if((y!=109 && y!=113) || (local_x>=9 && local_x<=11)) rgb=GOLD;
    end
   end else begin
    rgb=held[key]?PRESSED:WHITE;
    if(local_x==0 || local_x==19) rgb=BG;
    else if(local_x==18 || y>=125) rgb=held[key]?PRESSED_EDGE:EDGE;
    else if(y==86) rgb=WHITE;
   end
   case(key) 0:letter="C";1:letter="D";2:letter="E";3:letter="F";
    4:letter="G";5:letter="A";6:letter="B";default:letter="C";endcase
   digit=(octave_select==1)?"5":(octave_select==2)?"3":"4";
   if(key==7) digit=digit+1'b1;
   if(y>=116 && y<=122 && local_x>=5 && local_x<16) begin
    char_col=(local_x<11)?local_x-5'd5:local_x-5'd11;
    char_row=y-8'd116;ch=(local_x<11)?letter:digit;
    if(dot(glyph(ch,char_row[2:0]),char_col[2:0])) rgb=timbre_select?(held[key]?GOLD:TEXT):INK;
   end
   // Standard 2+3 black-key grouping, decoration only (no extra sensors).
   black_key=(x>=16 && x<=23)||(x>=36 && x<=43)||
             (x>=76 && x<=83)||(x>=96 && x<=103)||(x>=116 && x<=123);
   if(!timbre_select && black_key && y<=108) begin
    rgb=BLACK;
    if(y==86 || y==87 || y==106) rgb=BLACK_TOP;
   end
  end
  // 5x7 title fits in the previously unused top seven rows. Existing piano
  // spectrum, axes and keyboard pixels below this title remain unchanged.
  if(y<=6) begin
   char_row=y[2:0];ch=0;char_col=0;
   for(c=0;c<6;c=c+1) begin
    if(x>=4+c*6 && x<9+c*6) begin
     char_col=x-(4+c*6);
     if(timbre_select) case(c)
      0:ch="G";1:ch="U";2:ch="I";3:ch="T";4:ch="A";5:ch="R";
     endcase
     else case(c)
      0:ch="P";1:ch="I";2:ch="A";3:ch="N";4:ch="O";default:ch=0;
     endcase
    end
   end
   for(c=0;c<4;c=c+1) begin
    if(x>=132+c*6 && x<137+c*6) begin
     char_col=x-(132+c*6);
     case(c) 0:ch="O";1:ch="C";2:ch="T";
      3:ch=(octave_select==1)?"5":(octave_select==2)?"3":"4";
     endcase
    end
   end
   if(dot(glyph(ch,char_row),char_col)) rgb=timbre_select?GOLD:TEXT;
  end
  if(timbre_select && y>=10 && y<=18 && x>=110 && x<=146) begin
   rgb=BG;ch=0;char_col=0;char_row=y-8'd11;
   if(y>=11 && y<=17) begin
    for(c=0;c<6;c=c+1) begin
     if(x>=111+c*6 && x<116+c*6) begin
      char_col=x-(111+c*6);
      case(c) 0:ch="V";1:ch="I";2:ch="S";3:ch=0;4:ch="x";5:ch="4";endcase
     end
    end
    if(dot(glyph(ch,char_row),char_col)) rgb=GOLD;
   end
  end
 end
endmodule
`default_nettype wire
