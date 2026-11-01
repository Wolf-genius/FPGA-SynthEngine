`timescale 1ns/1ps
module real_timing_tb;
 reg clk=0,rst_n=0,rx=1;reg[7:0]gate=0;always #10 clk=~clk;
 wire tx,active,done,fault,stale,loading,valid,overflow;wire[7:0]led,addr,target;wire[8:0] count;wire[2:0]state;
 bluetooth_teach_control dut(.clk(clk),.rst_n(rst_n),.bt_rx(rx),.controls_valid(1'b1),.gate(gate),.bt_tx(tx),.led(led),
 .active(active),.done(done),.fault(fault),.input_stale(stale),.loading(loading),.song_valid(valid),.song_count(count),
 .lesson_step(addr),.target_mask(target),.state(state),.tx_overflow(overflow));
 task byte_in(input[7:0] b);integer j;begin rx=0;repeat(5208)@(negedge clk);
 for(j=0;j<8;j=j+1)begin rx=b[j];repeat(5208)@(negedge clk);end
 rx=1;repeat(5208)@(negedge clk);end endtask
 task line(input string s);integer j;begin for(j=0;j<s.len();j=j+1)byte_in(s[j]);byte_in(10);repeat(8)@(negedge clk);end endtask
 integer cycles=0,start_cycle,txfile,n;reg[7:0]got;
 always @(posedge clk)cycles=cycles+1;
 always @(negedge tx)if(rst_n)begin
 repeat(2604)@(posedge clk);#1;if(tx!==0)$fatal(1,"tx start");
 for(n=0;n<8;n=n+1)begin repeat(5208)@(posedge clk);#1;got[n]=tx;end
 repeat(5208)@(posedge clk);#1;if(tx!==1)$fatal(1,"tx stop");$fwrite(txfile,"%c",got);
 end
 initial begin
 txfile=$fopen("sim/real_uart.txt","wb");repeat(6)@(negedge clk);rst_n=1;
 line("PING");line("BEGIN,3");line("NOTE,80,2000,1000,100");
 line("NOTE,00,2,0,0");line("NOTE,01,2000,500,100");line("END");line("TEACH");wait(state==3);
 if(led!=128)$fatal(1,"real UART target");@(negedge clk);gate=128;
 @(negedge clk);if(addr!=1)$fatal(1,"1000ms note did not pass on first frame");
 wait(state==2);@(negedge clk);gate=0;wait(state==4);@(negedge clk);start_cycle=cycles;
 wait(addr==2);@(negedge clk);if(cycles-start_cycle!=100000)$fatal(1,"real 2ms rest wrong %0d",cycles-start_cycle);
 wait(state==3);repeat(2)@(negedge clk);if(led!=1)$fatal(1,"post-rest target led=%h target=%h addr=%d",led,target,addr);@(negedge clk);gate=1;
 @(negedge clk);if(!done||active||gate!=1)$fatal(1,"500ms last note must complete before release");
 repeat(1800000)@(negedge clk);$fclose(txfile);
 if(fault||overflow)$fatal(1,"real timing fault");
 $display("PASS actual hardware UART 5208 clocks/bit, 50MHz 2ms rest exactly 100000 clocks, 500/1000ms notes advance on first correct frame, DONE before release");$finish;
 end
 initial begin #300000000;$fatal(1,"real UART timeout");end
endmodule
