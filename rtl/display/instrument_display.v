`timescale 1ns/1ps
`default_nettype none
module instrument_display #(
 parameter [95:0] RAW_MIN_PACK={8{12'd128}},
 parameter [95:0] RAW_MAX_PACK={8{12'd3840}},
 parameter integer SPI_HALF_CYCLES=5,
 parameter integer RESET_LOW_CYCLES=5000000,
 parameter integer RESET_HIGH_CYCLES=2500000,
 parameter integer SLEEP_OUT_CYCLES=6000000,
 parameter integer PAGE_HOLD_CYCLES=500000
)(
 input wire clk,rst_n,controls_valid,timbre_select,
 input wire [1:0] octave_select,
 input wire [7:0] gate,
 input wire [95:0] control_raw_frame,
 input wire [127:0] envelopes,held_gains,
 input wire [23:0] states,
 output wire lcd_sck,lcd_sda,lcd_cs_n,lcd_rs,lcd_res_n
);
 wire [7:0] held_mask;
 wire [6:0] press_percent;
 wire [2:0] last_note;
 wire last_note_valid,publish;
 performance_monitor #(.RAW_MIN_PACK(RAW_MIN_PACK),.RAW_MAX_PACK(RAW_MAX_PACK)) observer(
  .clk(clk),.rst_n(rst_n),.controls_valid(controls_valid),.gate(gate),
  .control_raw_frame(control_raw_frame),.held_mask(held_mask),
  .press_percent(press_percent),.last_note(last_note),
  .last_note_valid(last_note_valid),.publish(publish));
 wire frame_start;
 wire [6:0] x;
 wire [7:0] y;
 wire [15:0] rgb;
 function [31:0] pressure_text;
  input [6:0] p;
  begin case(p)
   7'd0: pressure_text="0%  ";
   7'd1: pressure_text="1%  ";
   7'd2: pressure_text="2%  ";
   7'd3: pressure_text="3%  ";
   7'd4: pressure_text="4%  ";
   7'd5: pressure_text="5%  ";
   7'd6: pressure_text="6%  ";
   7'd7: pressure_text="7%  ";
   7'd8: pressure_text="8%  ";
   7'd9: pressure_text="9%  ";
   7'd10: pressure_text="10% ";
   7'd11: pressure_text="11% ";
   7'd12: pressure_text="12% ";
   7'd13: pressure_text="13% ";
   7'd14: pressure_text="14% ";
   7'd15: pressure_text="15% ";
   7'd16: pressure_text="16% ";
   7'd17: pressure_text="17% ";
   7'd18: pressure_text="18% ";
   7'd19: pressure_text="19% ";
   7'd20: pressure_text="20% ";
   7'd21: pressure_text="21% ";
   7'd22: pressure_text="22% ";
   7'd23: pressure_text="23% ";
   7'd24: pressure_text="24% ";
   7'd25: pressure_text="25% ";
   7'd26: pressure_text="26% ";
   7'd27: pressure_text="27% ";
   7'd28: pressure_text="28% ";
   7'd29: pressure_text="29% ";
   7'd30: pressure_text="30% ";
   7'd31: pressure_text="31% ";
   7'd32: pressure_text="32% ";
   7'd33: pressure_text="33% ";
   7'd34: pressure_text="34% ";
   7'd35: pressure_text="35% ";
   7'd36: pressure_text="36% ";
   7'd37: pressure_text="37% ";
   7'd38: pressure_text="38% ";
   7'd39: pressure_text="39% ";
   7'd40: pressure_text="40% ";
   7'd41: pressure_text="41% ";
   7'd42: pressure_text="42% ";
   7'd43: pressure_text="43% ";
   7'd44: pressure_text="44% ";
   7'd45: pressure_text="45% ";
   7'd46: pressure_text="46% ";
   7'd47: pressure_text="47% ";
   7'd48: pressure_text="48% ";
   7'd49: pressure_text="49% ";
   7'd50: pressure_text="50% ";
   7'd51: pressure_text="51% ";
   7'd52: pressure_text="52% ";
   7'd53: pressure_text="53% ";
   7'd54: pressure_text="54% ";
   7'd55: pressure_text="55% ";
   7'd56: pressure_text="56% ";
   7'd57: pressure_text="57% ";
   7'd58: pressure_text="58% ";
   7'd59: pressure_text="59% ";
   7'd60: pressure_text="60% ";
   7'd61: pressure_text="61% ";
   7'd62: pressure_text="62% ";
   7'd63: pressure_text="63% ";
   7'd64: pressure_text="64% ";
   7'd65: pressure_text="65% ";
   7'd66: pressure_text="66% ";
   7'd67: pressure_text="67% ";
   7'd68: pressure_text="68% ";
   7'd69: pressure_text="69% ";
   7'd70: pressure_text="70% ";
   7'd71: pressure_text="71% ";
   7'd72: pressure_text="72% ";
   7'd73: pressure_text="73% ";
   7'd74: pressure_text="74% ";
   7'd75: pressure_text="75% ";
   7'd76: pressure_text="76% ";
   7'd77: pressure_text="77% ";
   7'd78: pressure_text="78% ";
   7'd79: pressure_text="79% ";
   7'd80: pressure_text="80% ";
   7'd81: pressure_text="81% ";
   7'd82: pressure_text="82% ";
   7'd83: pressure_text="83% ";
   7'd84: pressure_text="84% ";
   7'd85: pressure_text="85% ";
   7'd86: pressure_text="86% ";
   7'd87: pressure_text="87% ";
   7'd88: pressure_text="88% ";
   7'd89: pressure_text="89% ";
   7'd90: pressure_text="90% ";
   7'd91: pressure_text="91% ";
   7'd92: pressure_text="92% ";
   7'd93: pressure_text="93% ";
   7'd94: pressure_text="94% ";
   7'd95: pressure_text="95% ";
   7'd96: pressure_text="96% ";
   7'd97: pressure_text="97% ";
   7'd98: pressure_text="98% ";
   7'd99: pressure_text="99% ";
   7'd100: pressure_text="100%";
   default: pressure_text="100%";
  endcase end
 endfunction
 reg [31:0] view_pressure_text;
 reg [7:0] view_held;
 reg [6:0] view_percent;
 reg [3:0] view_count;
 reg [2:0] view_note,view_state;
 reg view_note_valid,view_timbre;
 reg [1:0] view_octave;
 function [3:0] count_voices;
  input [127:0] env,gains;
  integer i;
  begin
   count_voices=0;
   for(i=0;i<8;i=i+1)
    if(env[i*16+:16]!=0 && gains[i*16+:16]!=0) count_voices=count_voices+1'b1;
  end
 endfunction
 wire [3:0] count_now=count_voices(envelopes,held_gains);
 // Snapshot once per LCD frame so text/bar/keys cannot tear across updates.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   view_held<=0; view_percent<=0; view_count<=0; view_pressure_text<="0%  ";
   view_note<=0; view_state<=0; view_note_valid<=0; view_timbre<=0; view_octave<=0;
  end else if(frame_start) begin
   view_timbre<=timbre_select; view_octave<=octave_select;
   view_held<=held_mask; view_percent<=press_percent; view_count<=count_now;
   view_pressure_text<=pressure_text(press_percent);
   view_note<=last_note; view_note_valid<=last_note_valid;
   view_state<=(envelopes[last_note*16+:16]==0)?3'd0:states[last_note*3+:3];
  end
 end
 instrument_renderer renderer(.x(x),.y(y),.held(view_held),.percent(view_percent),
  .pressure_text(view_pressure_text),.sound_count(view_count),.last_note(view_note),.last_valid(view_note_valid),
  .last_state(view_state),.timbre_select(view_timbre),.octave_select(view_octave),.rgb(rgb));
 lcd_panel_driver #(.SPI_HALF_CYCLES(SPI_HALF_CYCLES),
  .RESET_LOW_CYCLES(RESET_LOW_CYCLES),.RESET_HIGH_CYCLES(RESET_HIGH_CYCLES),
  .SLEEP_OUT_CYCLES(SLEEP_OUT_CYCLES),.PAGE_HOLD_CYCLES(PAGE_HOLD_CYCLES)) panel(
  .clk(clk),.rst_n(rst_n),.lcd_sck(lcd_sck),.lcd_sda(lcd_sda),
  .lcd_cs_n(lcd_cs_n),.lcd_rs(lcd_rs),.lcd_res_n(lcd_res_n),
  .pixel_rgb(rgb),.x(x),.y(y),.frame_start(frame_start));
endmodule
`default_nettype wire
