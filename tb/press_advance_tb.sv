`timescale 1ns/1ps
module press_advance_tb;
 localparam TICK=4,TIMEOUT=10;
 reg clk=0,rst_n=0,start=0,stop=0,cv=1;reg[7:0]gate=0;always #10 clk=~clk;
 wire[7:0]addr,target;wire active,done,fault,pass_pulse,wrong,stale;wire[2:0]state;
 reg[7:0]masks[0:255];reg[15:0]durations[0:255];reg[8:0]count=1;
 reg ready_enable=1,valid_enable=1;reg[7:0]read_addr=0,read_mask=0;
 reg[15:0]read_duration=0;reg read_last=0;
 always @(posedge clk)begin
  read_addr<=addr;read_mask<=masks[addr];read_duration<=durations[addr];
  read_last<=({1'b0,addr}+9'd1==count);
 end
 teach_ctrl #(.TICK_CYCLES(TICK),.FRAME_TIMEOUT_MS(TIMEOUT)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.stop(stop),.controls_valid(cv),.gate(gate),
 .song_addr(addr),.step_ready(ready_enable && read_addr==addr),.step_valid(valid_enable),
 .step_mask(read_mask),.step_duration_ms(read_duration),.step_last(read_last),
 .active(active),.done(done),.fault(fault),.target_mask(target),.step_pass(pass_pulse),
 .wrong_press(wrong),.input_stale(stale),.state(state));
 integer cycles=0,passes=0,i,m,saved,beginning;
 always @(posedge clk)begin cycles=cycles+1;#2;if(rst_n && pass_pulse)passes=passes+1;end
 task frame(input[7:0]keys);begin @(negedge clk);cv=1;gate=keys;@(negedge clk);end endtask
 task begin_lesson(input integer size);begin count=size;@(negedge clk);start=1;@(negedge clk);start=0;end endtask
 task wait_note(input[7:0]mask);begin wait(state==3);@(negedge clk);
  if(target!==mask||!active||fault)$fatal(1,"target mask/address");end endtask
 task correct_press(input[7:0]keys);integer pass_before;begin pass_before=passes;frame(keys);
  if(passes!=pass_before+1||!pass_pulse)$fatal(1,"correct press did not pass on its accepted frame");end endtask
 task end_lesson;begin @(negedge clk);stop=1;@(negedge clk);stop=0;gate=0;cv=1;
  if(active||done||fault||pass_pulse||target!=0||state!=0)$fatal(1,"STOP reset");end endtask
 initial begin
  for(i=0;i<256;i=i+1)begin masks[i]=1;durations[i]=500;end
  repeat(6)@(negedge clk);rst_n=1;
  // No note hold, including H=500, 1000 and 60000.
  masks[0]=1;durations[0]=500;masks[1]=1;durations[1]=1000;
  masks[2]=2;durations[2]=60000;masks[3]=5;masks[4]=5;
  frame(1);begin_lesson(5);wait(state==2);repeat(4)frame(1);
  if(addr!=0||passes!=0)$fatal(1,"preheld start key accepted");
  frame(0);wait_note(1);frame(2);if(addr!=0||!wrong)$fatal(1,"wrong press accepted");
  saved=passes;@(negedge clk);cv=0;gate=1;repeat(3)@(negedge clk);
  if(passes!=saved||addr!=0)$fatal(1,"input without controls_valid accepted");
  correct_press(1);wait_note(1);repeat(60)frame(1);
  if(addr!=1||passes!=1)$fatal(1,"long hold skipped a repeated note");
  frame(0);correct_press(1);wait_note(2);
  // Direct C4-to-D4 transition, without an all-zero frame.
  correct_press(2);wait_note(5);frame(1);if(addr!=3)$fatal(1,"partial chord passed");
  frame(7);if(addr!=3||!wrong)$fatal(1,"extra key passed");
  correct_press(5);wait_note(5);repeat(20)frame(5);
  if(addr!=4||passes!=4)$fatal(1,"held chord skipped repeat");
  frame(1);correct_press(5);
  if(!done||active||target!=0||gate!=5)$fatal(1,"last press must finish before release");
  repeat(10)frame(5);if(passes!=5)$fatal(1,"duplicate completion");end_lesson;
  // Rest duration and interruption still follow D exactly.
  masks[0]=0;durations[0]=3;begin_lesson(1);wait(state==4);
  @(negedge clk);beginning=cycles;wait(done);@(negedge clk);
  if(cycles-beginning!=3*TICK)$fatal(1,"rest duration changed");end_lesson;
  begin_lesson(1);wait(state==4);frame(2);
  if(state!=3||done||!wrong)$fatal(1,"wrong key did not cancel rest");
  frame(0);if(state!=4)$fatal(1,"rest did not restart");beginning=cycles;wait(done);@(negedge clk);
  if(cycles-beginning!=3*TICK)$fatal(1,"rest restart duration changed");end_lesson;
  // Timeout cannot approve cached or already held input.
  masks[0]=2;durations[0]=1000;begin_lesson(1);wait_note(2);frame(1);
  saved=passes;@(negedge clk);cv=0;gate=0;repeat(TICK*TIMEOUT+2)@(negedge clk);
  if(!stale||state!=2)$fatal(1,"stale input did not rearm");repeat(4)frame(2);
  if(state!=2||passes!=saved)$fatal(1,"held recovery key accepted");
  frame(0);wait_note(2);correct_press(2);if(!done)$fatal(1,"recovery press");end_lesson;
  // A new frame has priority at the watchdog deadline.
  begin_lesson(1);wait_note(2);@(negedge clk);cv=0;
  wait(dut.frame_age==dut.AGE_LAST);@(negedge clk);cv=1;gate=2;
  @(negedge clk);if(!done||stale)$fatal(1,"deadline frame lost");end_lesson;
  ready_enable=0;begin_lesson(1);repeat(8)frame(2);
  if(state!=1||target!=0||done)$fatal(1,"unready score read consumed");
  ready_enable=1;wait(state==2);frame(0);wait_note(2);correct_press(2);end_lesson;
  begin_lesson(1);wait_note(2);saved=passes;
  @(negedge clk);stop=1;start=1;gate=2;@(negedge clk);stop=0;start=0;
  if(state!=0||pass_pulse||done||active||passes!=saved)$fatal(1,"STOP priority");frame(0);
  // All 255 nonzero target masks, including every possible chord.
  for(m=1;m<256;m=m+1)begin
   masks[0]=m;durations[0]=(m%2)?500:1000;
   frame(0);begin_lesson(1);wait_note(m);saved=passes;
   frame(m^8'h80);if(passes!=saved||done)$fatal(1,"wrong mask %h",m);
   correct_press(m);if(!done)$fatal(1,"mask did not finish %h",m);end_lesson;
  end
  valid_enable=0;begin_lesson(1);wait(fault);if(active||target!=0)$fatal(1,"invalid metadata");
  end_lesson;valid_enable=1;durations[0]=0;begin_lesson(1);wait(fault);end_lesson;
  $display("PASS press advance: first correct frame; H=500/1000/60000 ignored; no zero between notes; repeats/chords/extra-key correction; 255 masks; exact rests; stale/recovery/deadline; tagged RAM; STOP; invalid metadata; passes=%0d",passes);$finish;
 end
 initial begin #2000000;$fatal(1,"press test timeout state=%0d addr=%0d",state,addr);end
endmodule
