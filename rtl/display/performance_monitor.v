`timescale 1ns/1ps
`default_nettype none
// Display-only observer. No ready/enable feeds back to ADC or audio.
// Normalize RAW_MIN..RAW_MAX to 0..100 for each held key; keep the maximum.
// A serial divider avoids additional DSP blocks and long combinational paths.
module performance_monitor #(
 parameter [95:0] RAW_MIN_PACK={8{12'd128}},
 parameter [95:0] RAW_MAX_PACK={8{12'd3840}}
)(
 input wire clk,rst_n,controls_valid,
 input wire [7:0] gate,
 input wire [95:0] control_raw_frame,
 output reg [7:0] held_mask,
 output reg [6:0] press_percent,
 output reg [2:0] last_note,
 output reg last_note_valid,
 output reg publish
);
 reg [7:0] previous_gate,frame_gate;
 reg [95:0] raw_saved;
 reg [2:0] lane;
 reg [2:0] state;
 reg [4:0] bits_left;
 reg [11:0] delta,divisor;
 reg [12:0] remainder;
 reg [19:0] quotient;
 reg [6:0] maximum;
 wire [11:0] raw=raw_saved[lane*12+:12];
 wire [11:0] minimum=RAW_MIN_PACK[lane*12+:12];
 wire [11:0] limit=RAW_MAX_PACK[lane*12+:12];
 wire [13:0] trial={remainder,quotient[19]};
 wire subtract_bit=trial>={2'b0,divisor};
 wire [19:0] delta_wide={8'b0,delta};
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   held_mask<=0; press_percent<=0; last_note<=0; last_note_valid<=0;
   previous_gate<=0; frame_gate<=0; raw_saved<=0; lane<=0; state<=0;
   bits_left<=0; delta<=0; divisor<=1; remainder<=0; quotient<=0;
   maximum<=0; publish<=0;
  end else begin
   publish<=0;
   if(controls_valid) begin
    previous_gate<=gate; frame_gate<=gate; raw_saved<=control_raw_frame;
    // Simultaneous note-ons: highest channel number wins the status line.
    for(i=0;i<8;i=i+1) if(gate[i] && !previous_gate[i]) begin
     last_note<=i; last_note_valid<=1;
    end
    lane<=0; maximum<=0; state<=1;
   end else case(state)
    1: begin
     divisor<=(limit>minimum)?limit-minimum:12'd1;
     if(!frame_gate[lane] || raw<=minimum || limit<=minimum) delta<=0;
     else if(raw>=limit) delta<=limit-minimum;
     else delta<=raw-minimum;
     state<=2;
    end
    2: begin
     quotient<=(delta_wide<<6)+(delta_wide<<5)+(delta_wide<<2);
     remainder<=0; bits_left<=20; state<=3;
    end
    3: begin
     remainder<=subtract_bit ? trial-{2'b0,divisor} : trial;
     quotient<={quotient[18:0],subtract_bit};
     bits_left<=bits_left-1'b1;
     if(bits_left==1) state<=4;
    end
    4: begin
     if(lane==7) begin
      press_percent<=(quotient[6:0]>maximum)?quotient[6:0]:maximum;
      held_mask<=frame_gate; publish<=1; state<=0;
     end else begin
      if(quotient[6:0]>maximum) maximum<=quotient[6:0];
      lane<=lane+1'b1; state<=1;
     end
    end
    default: state<=0;
   endcase
  end
 end
endmodule
`default_nettype wire
