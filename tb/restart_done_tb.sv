`timescale 1ns/1ps
module restart_done_tb;
 reg clk=0,rst_n=0,cv=0,done_in=0;reg[3:0]cmd=0;always #10 clk=~clk;
 wire loading,valid,start,stop,ready,sv,last,rv;wire[8:0]count;wire[7:0]mask;wire[15:0]duration,crc;wire[4:0]reply;
 download_score_store d(.clk(clk),.rst_n(rst_n),.cmd_valid(cv),.cmd(cmd),.count(9'd1),.record({8'd1,16'd2,16'd1,8'd100}),
 .crc_present(1'b0),.crc_value(16'd0),.teach_active(1'b0),.teach_done(done_in),.teach_fault(1'b0),.lesson_addr(8'd0),
 .loading(loading),.song_valid(valid),.song_count(count),.teach_start(start),.teach_stop(stop),.step_ready(ready),
 .step_valid(sv),.step_last(last),.step_mask(mask),.step_duration_ms(duration),.reply_valid(rv),.reply_code(reply),.running_crc(crc));
 integer done_count=0;
 always @(negedge clk)if(rv&&reply==15)done_count=done_count+1;
 task command(input[3:0]c);begin @(negedge clk);cmd=c;cv=1;@(negedge clk);cv=0;repeat(55)@(negedge clk);end endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;command(2);command(3);command(4);if(!valid)$fatal(1,"load");
 // Previous tutorial completes just as a new TEACH command is accepted.
 @(negedge clk);cmd=10;cv=1;@(posedge clk);#1;done_in=1;
 @(negedge clk);cv=0;@(posedge clk);#1;done_in=0;repeat(8)@(negedge clk);
 if(done_count!=0)$fatal(1,"Old DONE leaked into restarted tutorial");
 // A later genuine completion must still report exactly once.
 done_in=1;repeat(8)@(negedge clk);if(done_count!=1)$fatal(1,"Missing genuine DONE");
 $display("PASS same-edge TEACH restart suppresses previous DONE; genuine completion reports once");$finish;
 end
endmodule
