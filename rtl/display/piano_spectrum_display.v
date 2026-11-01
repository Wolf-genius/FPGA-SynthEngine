`timescale 1ns/1ps
`default_nettype none
// Native panel remains 128x160/MADCTL=c0. Rotate rendering coordinates only.
// Turn the physical module clockwise 90 degrees for the landscape layout.
module piano_spectrum_display #(
 parameter integer SPI_HALF_CYCLES=5,
 parameter integer RESET_LOW_CYCLES=5000000,
 parameter integer RESET_HIGH_CYCLES=2500000,
 parameter integer SLEEP_OUT_CYCLES=6000000,
 parameter integer PAGE_HOLD_CYCLES=500000
)(
 input wire clk,rst_n,controls_valid,
 input wire [7:0] gate,
 input wire [1:0] octave_select,
 input wire timbre_select,
 input wire signed [15:0] mixed_sample,
 input wire mixed_valid,
 output wire lcd_sck,lcd_sda,lcd_cs_n,lcd_rs,lcd_res_n,
 output wire spectrum_overrun
);
 wire [902:0] latest_heights;
 wire [902:0] latest_guitar_heights;
 wire spectrum_valid;
 audio_spectrum analyzer(.clk(clk),.rst_n(rst_n),.sample_valid(mixed_valid),
  .sample_data(mixed_sample),.heights(latest_heights),.guitar_heights(latest_guitar_heights),
  .spectrum_valid(spectrum_valid),.overrun(spectrum_overrun));
 reg [7:0] held;
 reg [7:0] view_held;
 reg [1:0] view_octave;
 reg view_timbre;
 reg [902:0] view_heights;
 wire frame_start;
 wire [6:0] native_x;
 wire [7:0] native_y;
 wire [7:0] landscape_x=8'd159-native_y;
 wire [7:0] landscape_y={1'b0,native_x};
 wire [15:0] rgb;
 reg [7:0] pixel_x,pixel_y;
 reg [6:0] pixel_height,pixel_previous;
 wire [7:0] bin_address=landscape_x-8'd16;
 wire [7:0] previous_address=(bin_address==0)?8'd0:bin_address-1'b1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   held<=0;view_held<=0;view_octave<=0;view_timbre<=0;view_heights<=0;
   pixel_x<=0;pixel_y<=0;pixel_height<=0;pixel_previous<=0;
  end
  else begin
   // Separate height-table selection from the final palette/font comparisons.
   pixel_x<=landscape_x;pixel_y<=landscape_y;
   if(landscape_x>=16 && landscape_x<=144) begin
    pixel_height<=view_heights[bin_address*7+:7];
    pixel_previous<=view_heights[previous_address*7+:7];
   end else begin pixel_height<=0;pixel_previous<=0;end
   if(controls_valid) held<=gate;
   if(frame_start) begin
    view_held<=controls_valid?gate:held;
    view_octave<=octave_select;view_timbre<=timbre_select;
    view_heights<=timbre_select?latest_guitar_heights:latest_heights;
   end
  end
 end
 piano_spectrum_renderer #(.PRESELECTED_HEIGHTS(1)) renderer(.x(pixel_x),.y(pixel_y),.held(view_held),
  .octave_select(view_octave),.timbre_select(view_timbre),.heights(903'd0),
  .height_current(pixel_height),.height_previous(pixel_previous),.rgb(rgb));
 spectrum_panel_driver #(.SPI_HALF_CYCLES(SPI_HALF_CYCLES),
  .RESET_LOW_CYCLES(RESET_LOW_CYCLES),.RESET_HIGH_CYCLES(RESET_HIGH_CYCLES),
  .SLEEP_OUT_CYCLES(SLEEP_OUT_CYCLES),.PAGE_HOLD_CYCLES(PAGE_HOLD_CYCLES)) panel(
  .clk(clk),.rst_n(rst_n),.lcd_sck(lcd_sck),.lcd_sda(lcd_sda),
  .lcd_cs_n(lcd_cs_n),.lcd_rs(lcd_rs),.lcd_res_n(lcd_res_n),
  .pixel_rgb(rgb),.x(native_x),.y(native_y),.frame_start(frame_start));
endmodule
`default_nettype wire
