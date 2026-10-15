`timescale 1ns/1ps
module tb_controls;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, raw_valid=0, sample_ce=0;
    reg [11:0] raw_data=0;
    wire [7:0] gate, sample_gate;
    wire [127:0] key_gain, sample_gain;
    wire controls_valid;
    pressure_ch0_controls dut(.*);
    control_frame_receiver receiver(.*);
    integer fd, trace, n, r, v, raw, ce, eg, gain, ev, sg, s_gain, count=0;
    initial begin
        $dumpfile("controls.vcd"); $dumpvars(0,tb_controls);
        fd=$fopen("vectors.txt","r");
        trace=$fopen("actual.csv","w");
        if (!fd || !trace) $fatal(1,"Cannot open vectors/trace");
        $fdisplay(trace,"cycle,gate,gain,valid,sample_gate,sample_gain");
        while (!$feof(fd)) begin
            n=$fscanf(fd,"%d %d %d %d %d %d %d %d %d\n",r,v,raw,ce,eg,gain,ev,sg,s_gain);
            if(n!=9) $fatal(1,"Malformed vector");
            @(negedge clk);
            rst_n=r; raw_valid=v; raw_data=raw; sample_ce=ce;
            @(posedge clk); #1;
            if (gate !== eg[7:0] || key_gain !== {112'd0,gain[15:0]} || controls_valid !== ev[0]
                || sample_gate !== sg[7:0] || sample_gain !== {112'd0,s_gain[15:0]})
                $fatal(1,"Mismatch cycle=%0d raw=%0d gate=%h/%h gain=%0d/%0d valid=%b/%b receiver=%h/%h %0d/%0d",
                    count,raw,gate,eg,key_gain,gain,controls_valid,ev,sample_gate,sg,sample_gain,s_gain);
            $fdisplay(trace,"%0d,%0d,%0d,%0d,%0d,%0d",count,gate,key_gain,controls_valid,sample_gate,sample_gain);
            count=count+1;
        end
        $fclose(fd); $fclose(trace);
        $display("PASS ALL controls cycles=%0d",count);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Watchdog"); end
endmodule
