`timescale 1ns/1ps
module download_teach_tb;
 localparam CPT=8,MS=32;
 reg clk=0,rst_n=0,rx=1,cv=1;reg[7:0] gate=0;always #10 clk=~clk;
 wire tx,active,done,fault,stale,loading,valid,overflow;wire[7:0]led,addr,target;wire[8:0] count;wire[2:0]state;
 bluetooth_teach_control #(.CLKS_PER_BIT(CPT),.TICK_CYCLES(MS)) dut(
 .clk(clk),.rst_n(rst_n),.bt_rx(rx),.controls_valid(cv),.gate(gate),.bt_tx(tx),.led(led),
 .active(active),.done(done),.fault(fault),.input_stale(stale),.loading(loading),.song_valid(valid),
 .song_count(count),.lesson_step(addr),.target_mask(target),.state(state),.tx_overflow(overflow));
 reg[7:0] stimulus[0:8191];integer f,size,j,i,k,txfile;
 task byte_in(input[7:0] b);integer n;begin
 rx=0;repeat(CPT)@(negedge clk);for(n=0;n<8;n=n+1)begin rx=b[n];repeat(CPT)@(negedge clk);end
 rx=1;repeat(CPT)@(negedge clk);end endtask
 task line(input string s);integer n;begin for(n=0;n<s.len();n=n+1)byte_in(s[n]);byte_in(10);repeat(12)@(negedge clk);end endtask
 task upload(input integer which);integer n;begin
 if(which==0)begin f=$fopen("sim/a_count.txt","r");j=$fscanf(f,"%d",size);$fclose(f);$readmemh("sim/a.hex",stimulus,0,size-1);end
 else begin f=$fopen("sim/b_count.txt","r");j=$fscanf(f,"%d",size);$fclose(f);$readmemh("sim/b.hex",stimulus,0,size-1);end
 for(n=0;n<size;n=n+1)byte_in(stimulus[n]);repeat(20)@(negedge clk);
 end endtask
 task wait_target(input[7:0] mask);begin
 wait(state==3);@(negedge clk);
 if(target!==mask||led!==mask)$fatal(1,"RAM target mismatch addr=%0d got=%h exp=%h",addr,target,mask);
 end endtask
 task complete_note(input[7:0]mask,input integer legacy_ms);integer prior_addr;begin
 wait_target(mask);prior_addr=addr;gate=mask;@(negedge clk);
 if(!done && addr!=prior_addr+1)$fatal(1,"press did not advance immediately");
 repeat(3)@(negedge clk);gate=0;@(negedge clk);
 end endtask
 reg[7:0] got;integer bitn;
 always @(negedge tx)if(rst_n)begin
 repeat(CPT/2)@(posedge clk);#1;if(tx!==0)$fatal(1,"tx start");
 for(bitn=0;bitn<8;bitn=bitn+1)begin repeat(CPT)@(posedge clk);#1;got[bitn]=tx;end
 repeat(CPT)@(posedge clk);#1;if(tx!==1)$fatal(1,"tx stop");$fwrite(txfile,"%c",got);
 end
 always @(negedge clk)if(rst_n && (fault||overflow))$fatal(1,"unexpected fault/overflow");
 initial begin
 txfile=$fopen("sim/teach_uart.txt","wb");repeat(6)@(negedge clk);rst_n=1;
 line("PING");line("STATUS");line("TEACH");if(active||led!=0)$fatal(1,"empty teach");
 line("PLAY");line("LEDTEST");line("FREE");
 line("BEGIN,1");line("TEACH");if(active)$fatal(1,"teach during load");line("NOTE,01,4,2,100");line("END,0000");
 if(valid)$fatal(1,"bad CRC accepted");
 upload(0);if(!valid||count!=7||led!=0)$fatal(1,"commit");
 line("TEACH");wait_target(8'h80);line("STATUS");line("BEGIN,1");if(!valid||loading||!active)$fatal(1,"active song overwritten");
 gate=1;repeat(200)@(negedge clk);if(addr!=0||state!=3)$fatal(1,"wrong key");
 cv=0;repeat(MS*11)@(negedge clk);
 if(!stale||state!=2||addr!=0)$fatal(1,"stale input");
 gate=128;cv=1;repeat(10)@(negedge clk);if(state!=2)$fatal(1,"release after stale");
 gate=0;wait(state==3);line("STOP");if(active||!valid)$fatal(1,"stop preserve");line("TEACH");
 complete_note(128,4);complete_note(5,3);complete_note(1,2);complete_note(1,2);
 for(i=4;i<7;i=i+1)begin
 wait(addr==i && target==0);if(addr!=i||target!=0)$fatal(1,"rest decode");
 gate=0;wait(state==4);@(negedge clk);repeat(2*MS-1)@(negedge clk);
 if(state!=4)$fatal(1,"rest early");@(negedge clk);
 end
 wait(done);repeat(10)@(negedge clk);line("STATUS");if(active||!valid||addr!=6)$fatal(1,"completion");
 line("TEACH");wait_target(128);line("STOP");
 upload(1);if(!valid||count!=256)$fatal(1,"256 commit");line("TEACH");
 for(i=0;i<256;i=i+1)begin complete_note(1<<(i%8),1);end
 wait(done);repeat(10)@(negedge clk);if(addr!=255)$fatal(1,"256 wrap");
 line("STATUS");line("TEACH");wait_target(1);repeat(3000)@(negedge clk);gate=1;wait(addr==1);
 @(negedge clk);rst_n=0;#1;if(led!==0)$fatal(1,"reset light");repeat(5)@(negedge clk);gate=0;rst_n=1;
 line("TEACH");if(valid||active)$fatal(1,"reset invalidation");
 line("BEGIN,1");line("NOTE,01,4,2,100");line("STOP");line("STATUS");if(valid||loading)$fatal(1,"cancel upload");
 repeat(6000)@(negedge clk);$fclose(txfile);
 $display("PASS UART->CRC/RAM->real key tutorial->LED: custom notes, chords, repeats, immediate correct presses, wrong/stale, exact rest D, stop/restart/reset, 256 records");$finish;
 end
 initial begin #150000000;$fatal(1,"timeout state=%0d addr=%0d",state,addr);end
endmodule
