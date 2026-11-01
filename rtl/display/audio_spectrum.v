`timescale 1ns/1ps
`default_nettype none
// 256-point Hann-windowed serial DFT of the ACTUAL mixed PCM. No note lookup.
// One block every 41.943 ms; 129 real-spectrum bins, 0..3051.758 Hz.
// Two DFT multipliers are time-shared across all bins; no CPU/vendor FFT IP.
module audio_spectrum(
 input wire clk,rst_n,sample_valid,
 input wire signed [15:0] sample_data,
 output reg [902:0] heights,
 output reg [902:0] guitar_heights,
 output reg spectrum_valid,
 output wire overrun
);
 wire signed [15:0] filtered_data;
 wire filtered_valid,filter_overrun;
 spectrum_decimator filter(.clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),
  .sample_data(sample_data),.filtered_data(filtered_data),.filtered_valid(filtered_valid),.overrun(filter_overrun));
 reg signed [15:0] hann[0:255],cosine[0:255],sine[0:255];
 reg signed [15:0] samples[0:511];
 initial begin
  $readmemh("tables/spectrum_hann256.hex",hann);
  $readmemh("tables/spectrum_cos256.hex",cosine);
  $readmemh("tables/spectrum_sin256.hex",sine);
 end
 reg capture_bank,ready_bank,read_bank,block_ready,analysis_overrun;
 reg [7:0] capture_index,window_index;
 reg window_bank,window_valid;
 reg signed [31:0] window_product;
 reg [3:0] state;
 reg [7:0] bin,index,phase;
 reg signed [15:0] a,br,bi;
 reg signed [31:0] pr,pi;
 reg signed [39:0] ar,ai;
 reg [39:0] abs_re,abs_im;
 reg [39:0] max_registered,min_registered;
 reg [19:0] amplitude;
 reg [6:0] height_registered;
 reg [902:0] work_heights;
 reg [902:0] work_guitar_heights;
 reg [6:0] guitar_height_registered;
 wire [39:0] max_abs=(abs_re>abs_im)?abs_re:abs_im;
 wire [39:0] min_abs=(abs_re>abs_im)?abs_im:abs_re;
 wire [40:0] magnitude={1'b0,max_registered}+({1'b0,min_registered}>>1);
 assign overrun=filter_overrun|analysis_overrun;
 localparam IDLE=0,READ=1,MULT=2,ADD=3,ABS=4,ORDER=5,MAG=6,LEVEL=7,STORE=8,PUBLISH=9;
 // Fixed logarithmic display scale (not auto-normalized). Approximate magnitude
 // max(|Re|,|Im|)+min/2; <16 PCM units hidden; 6 pixels per factor of two.
 function [2:0] fractional_height;
  input [2:0] v;
  begin case(v)
   0,1:fractional_height=0;2:fractional_height=1;3:fractional_height=2;
   4,5:fractional_height=3;6:fractional_height=4;default:fractional_height=5;
  endcase end
 endfunction
 function [6:0] level;
  input [21:0] value;
  begin
   if(|value[21:14]) level=60;
   else casez(value[13:4])
    10'b1?????????:level=7'd55+fractional_height(value[12:10]);
    10'b01????????:level=7'd49+fractional_height(value[11:9]);
    10'b001???????:level=7'd43+fractional_height(value[10:8]);
    10'b0001??????:level=7'd37+fractional_height(value[9:7]);
    10'b00001?????:level=7'd31+fractional_height(value[8:6]);
    10'b000001????:level=7'd25+fractional_height(value[7:5]);
    10'b0000001???:level=7'd19+fractional_height(value[6:4]);
    10'b00000001??:level=7'd13+fractional_height(value[5:3]);
    10'b000000001?:level=7'd7+fractional_height(value[4:2]);
    10'b0000000001:level=7'd1+fractional_height(value[3:1]);
    default:level=0;
   endcase
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   capture_bank<=0;ready_bank<=0;read_bank<=0;block_ready<=0;analysis_overrun<=0;
   capture_index<=0;window_index<=0;window_bank<=0;window_valid<=0;window_product<=0;
   heights<=0;work_heights<=0;guitar_heights<=0;work_guitar_heights<=0;
   guitar_height_registered<=0;spectrum_valid<=0;state<=IDLE;
   bin<=0;index<=0;phase<=0;a<=0;br<=0;bi<=0;pr<=0;pi<=0;ar<=0;ai<=0;abs_re<=0;abs_im<=0;
   max_registered<=0;min_registered<=0;amplitude<=0;height_registered<=0;
  end else begin
   spectrum_valid<=0;block_ready<=0;window_valid<=filtered_valid;
   if(filtered_valid) begin
    window_product<=filtered_data*$signed(hann[capture_index]);
    window_index<=capture_index;window_bank<=capture_bank;
    capture_index<=capture_index+1'b1;
    if(capture_index==255) capture_bank<=~capture_bank;
   end
   if(window_valid) begin
    samples[{window_bank,window_index}]<=window_product[30:15];
    if(window_index==255) begin
     if(state!=IDLE) analysis_overrun<=1;
     else begin block_ready<=1;ready_bank<=window_bank;end
    end
   end
   case(state)
    IDLE: if(block_ready) begin
     read_bank<=ready_bank;bin<=0;index<=0;phase<=0;ar<=0;ai<=0;state<=READ;
    end
    READ: begin
     a<=samples[{read_bank,index}];br<=cosine[phase];bi<=sine[phase];state<=MULT;
    end
    MULT: begin pr<=a*br;pi<=a*bi;state<=ADD;end
    ADD: begin
     ar<=ar+{{8{pr[31]}},pr};ai<=ai+{{8{pi[31]}},pi};
     if(index==255) state<=ABS;
     else begin index<=index+1'b1;phase<=phase+bin;state<=READ;end
    end
    ABS: begin abs_re<=ar[39]?-ar:ar;abs_im<=ai[39]?-ai:ai;state<=ORDER;end
    ORDER: begin max_registered<=max_abs;min_registered<=min_abs;state<=MAG;end
    MAG: begin amplitude<=magnitude[40:21];state<=LEVEL;end
    // Two display scales from the SAME DFT. Widen before shifting, so x4
    // cannot wrap. This path never changes PCM sent to the amplifier.
    LEVEL: begin
     height_registered<=level({2'b00,amplitude});
     guitar_height_registered<=level({amplitude,2'b00});state<=STORE;
    end
    STORE: begin
     // Hide DC so sensor/synthesis offsets cannot masquerade as a low note.
     work_heights[bin*7+:7]<=(bin==0)?7'd0:height_registered;
     work_guitar_heights[bin*7+:7]<=(bin==0)?7'd0:guitar_height_registered;
     if(bin==128) state<=PUBLISH;
     else begin bin<=bin+1'b1;index<=0;phase<=0;ar<=0;ai<=0;state<=READ;end
    end
    PUBLISH: begin heights<=work_heights;guitar_heights<=work_guitar_heights;
     spectrum_valid<=1;state<=IDLE;end
    default: ;
   endcase
  end
 end
endmodule
`default_nettype wire
