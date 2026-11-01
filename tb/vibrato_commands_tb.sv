`timescale 1ns/1ps
module vibrato_commands_tb;
 localparam CPT=8;
 reg clk=0,rst_n=0,rx=1;reg[7:0]gate=0;always #10 clk=~clk;
 wire tx,active,done,fault,stale,loading,valid,overflow,vibrato_enable;
 wire[7:0]led,addr,target;wire[8:0]count;wire[2:0]state;
 bluetooth_teach_control #(.CLKS_PER_BIT(CPT),.TICK_CYCLES(32)) dut(
 .clk(clk),.rst_n(rst_n),.bt_rx(rx),.controls_valid(1'b1),.gate(gate),.bt_tx(tx),.led(led),
 .active(active),.done(done),.fault(fault),.input_stale(stale),.loading(loading),.song_valid(valid),
 .song_count(count),.lesson_step(addr),.target_mask(target),.state(state),
 .vibrato_enable(vibrato_enable),.tx_overflow(overflow));
 task byte_in(input[7:0]b);integer k;begin
  rx=0;repeat(CPT)@(negedge clk);for(k=0;k<8;k=k+1)begin rx=b[k];repeat(CPT)@(negedge clk);end
  rx=1;repeat(CPT)@(negedge clk);
 end endtask
 task line(input string s);integer k;begin
  for(k=0;k<s.len();k=k+1)byte_in(s[k]);byte_in(10);repeat(2000)@(negedge clk);
 end endtask
 integer f,k;reg[7:0]got;
 always @(negedge tx)if(rst_n)begin
  repeat(CPT/2)@(posedge clk);#1;if(tx!==0)$fatal(1,"TX start");
  for(k=0;k<8;k=k+1)begin repeat(CPT)@(posedge clk);#1;got[k]=tx;end
  repeat(CPT)@(posedge clk);#1;if(tx!==1)$fatal(1,"TX stop");$fwrite(f,"%c",got);
 end
 always @(negedge clk)if(rst_n && (fault||overflow))$fatal(1,"unexpected fault");
 initial begin
  f=$fopen("sim/vibrato_uart.txt","wb");repeat(6)@(negedge clk);rst_n=1;
  if(vibrato_enable)$fatal(1,"power-on default must be off");
  line("PING");line("VIBSTAT");line("VIBON");if(!vibrato_enable)$fatal(1,"enable without song");
  line("VIBSTAT");line("STATUS");line("VIBOFF");line("VIBSTAT");
  if(vibrato_enable)$fatal(1,"disable");
  line("BEGIN,1");line("VIBON");if(!loading||valid||!vibrato_enable)$fatal(1,"ON altered download");
  line("NOTE,80,1000,1000,100");line("VIBSTAT");line("VIBOFF");
  line("END,D9A2");if(!valid||count!=1||vibrato_enable)$fatal(1,"FX corrupted CRC/commit");
  line("TEACH");if(!active||target!=128||addr!=0)$fatal(1,"TEACH");
  line("VIBON");line("VIBSTAT");line("VIBOFF");line("VIBSTAT");
  if(!active||addr!=0||!valid||vibrato_enable)$fatal(1,"FX altered tutorial");
  gate=128;wait(done);repeat(2000)@(negedge clk);line("STATUS");
  line("TEACH");line("VIBON");line("STOP");line("VIBSTAT");
  if(active||!valid||!vibrato_enable||led!=0)$fatal(1,"STOP must preserve FX and song");
  line("VIBOFF");line("VIBON,1");line("VIBOFFX");line("vibon");
  if(vibrato_enable)$fatal(1,"invalid command changed FX");
  rst_n=0;gate=0;repeat(6)@(negedge clk);rst_n=1;
  if(vibrato_enable||valid||led!=0)$fatal(1,"reset defaults");
  line("VIBSTAT");line("STATUS");repeat(3000)@(negedge clk);$fclose(f);
  $display("PASS Bluetooth VIBON/VIBOFF/VIBSTAT: default off, no-song control, download CRC preserved, active teaching unchanged, STOP independent, invalid commands, reset and independent UART decode");$finish;
 end
 initial begin #5000000;$fatal(1,"vibrato command timeout");end
endmodule
