`timescale 1ns/1ps
module audio_vibrato_tb;
 localparam N=163840;
 reg clk=0,rst_n=0,enable=0,in_valid=0;reg signed[15:0]in_sample=0;
 always #10 clk=~clk;
 wire signed[15:0]out_sample;wire out_valid,overrun;
 audio_vibrato dut(.*);
 reg[15:0]stimulus[0:N-1];reg enabled[0:N-1];
 integer accepted=0,returned=0,cycles=0,i,f;
 integer accepted_cycle[0:N+255];reg logging=1;
 reg[31:0]saved_phase;reg[8:0]saved_wet;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(!rst_n)begin accepted=0;returned=0;end
  else begin
   if(in_valid && dut.state==0)begin accepted_cycle[accepted]=cycles;accepted=accepted+1;end
   #2;
   if(out_valid)begin
    if(returned>=accepted || cycles-accepted_cycle[returned]!=7)$fatal(1,"sample/valid latency mismatch");
    if(^out_sample===1'bx)$fatal(1,"unknown audio sample");
    if(logging)$fwrite(f,"%0d %0d %0d\n",returned,out_sample,dut.mix_level);
    returned=returned+1;
   end
  end
 end
 task reset_dut;begin @(negedge clk);rst_n=0;in_valid=0;repeat(3)@(negedge clk);
  if(out_valid||overrun||dut.wet_amount!=0||dut.filled!=0)$fatal(1,"reset state");rst_n=1;end endtask
 task one(input signed[15:0]x);begin
  @(negedge clk);in_sample=x;in_valid=1;@(negedge clk);in_valid=0;
  wait(out_valid);@(negedge clk);
 end endtask
 initial begin
  $readmemh("sim/vibrato_input.hex",stimulus);$readmemh("sim/vibrato_enable.hex",enabled);
  f=$fopen("sim/vibrato_samples.txt","w");repeat(5)@(negedge clk);rst_n=1;
  for(i=0;i<N;i=i+1)begin
   enable=enabled[i];in_sample=stimulus[i];in_valid=1;
   @(negedge clk);in_valid=0;repeat(15)@(negedge clk);
  end
  wait(returned==N);if(overrun)$fatal(1,"unexpected overrun");$fclose(f);logging=0;
  saved_phase=dut.lfo_phase;saved_wet=dut.wet_amount;enable=1;
  repeat(50)@(negedge clk);
  if(dut.lfo_phase!=saved_phase||dut.wet_amount!=saved_wet)$fatal(1,"LFO/ramp advanced without a sample");
  reset_dut;enable=1;
  for(i=0;i<140;i=i+1)begin one(0);if(out_sample!==0)$fatal(1,"uninitialized history leaked after reset");end
  reset_dut;enable=0;
  @(negedge clk);in_sample=12345;in_valid=1;
  @(negedge clk);in_sample=-22222;
  @(negedge clk);in_valid=0;wait(out_valid);@(negedge clk);
  if(!overrun||out_sample!=12345||accepted!=1||returned!=1)$fatal(1,"busy input handling");
  reset_dut;one(-32768);if(out_sample!==-16'sd32768)$fatal(1,"signed dry bypass");
  $display("PASS audio vibrato: %0d waveform samples; exact 7-clock data/valid latency; signed extrema; bypass; RAM warmup; ramps; reset/zero silence; idle LFO; busy overrun",N);$finish;
 end
 initial begin #60000000;$fatal(1,"vibrato unit timeout returned=%0d",returned);end
endmodule
