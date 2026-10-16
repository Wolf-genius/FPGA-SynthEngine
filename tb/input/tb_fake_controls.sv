`timescale 1ns/1ps
`default_nettype none
module tb_fake_controls #(parameter integer FRAME_CYCLES=40, TOTAL_FRAMES=802);
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    wire [7:0] gate;
    wire [127:0] key_gain;
    wire controls_valid;
    wire [8:0] scenario_frame;
    fake_four_key_controls #(.FRAME_CYCLES(FRAME_CYCLES)) dut(.*);
    integer f=0,cursor=0,i;
    reg [7:0] mask;
    reg [127:0] gain;
    time previous=0,pulse=0;
    always @(posedge controls_valid) begin
        if($time-previous!=FRAME_CYCLES*20) $fatal(1,"Fake cadence");
        previous=$time; pulse=$time;
        // Independently describe expected gate masks and individual gains.
        mask=0; gain=0;
        if(cursor>=10 && cursor<=29) mask=1;
        if(cursor>=30 && cursor<=49) mask=3;
        if(cursor>=50 && cursor<=129) mask=15;
        if(cursor>=130 && cursor<=149) mask=13;
        if(cursor>=150 && cursor<=199) mask=15;
        if(cursor>=200 && cursor<=209) mask=14+(cursor%2);
        for(i=0;i<4;i=i+1) if(mask[i]) gain[16*i+:16]=32768;
        if(cursor>=170 && cursor<=184) gain[47:32]=49152;
        if(cursor>=185 && cursor<=199) gain[47:32]=16384;
        if(gate!==mask || key_gain!==gain || scenario_frame!==cursor[8:0]) $fatal(1,"Fake sequence frame=%0d",cursor);
        cursor=(cursor+1)%400; f=f+1;
    end
    always @(negedge controls_valid) if(rst_n && pulse && $time-pulse!=20) $fatal(1,"Fake valid width");
    initial begin
        $dumpfile("fake.vcd"); $dumpvars(0,rst_n,gate,key_gain,controls_valid,scenario_frame);
        repeat(5) @(negedge clk); rst_n=1; previous=$time-10;
        wait(f==TOTAL_FRAMES); @(negedge clk); rst_n=0;
        #1; if(gate!==0 || key_gain!==0 || controls_valid) $fatal(1,"Fake reset not silent");
        repeat(3) @(negedge clk); rst_n=1; previous=$time-10; cursor=0;
        wait(f==TOTAL_FRAMES+2); repeat(2) @(negedge clk);
        $display("PASS ALL fake_controls frames=%0d frame_cycles=%0d reset_restart=1",f,FRAME_CYCLES);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Fake test timeout"); end
endmodule
`default_nettype wire
