`timescale 1ns/1ps
`default_nettype none
module tb_frames #(
    parameter integer ACTIVE_KEYS=4,
    parameter [95:0] TON_PACK={8{12'd256}}, TOFF_PACK={8{12'd128}},
    parameter [95:0] RAW_MIN_PACK={8{12'd128}}, RAW_MAX_PACK={8{12'd3840}},
    parameter [127:0] MIN_GAIN_PACK={8{16'd4096}}
);
    reg clk=0, rst_n=0, frame_valid=0, frame_cancel=0, sample_ce=0;
    reg [95:0] raw_frame=0;
    always #10 clk=~clk;
    wire [7:0] gate,sample_gate;
    wire [127:0] key_gain,sample_gain;
    wire controls_valid;
    wire [95:0] control_raw_frame;
    pressure_frame_controls #(.ACTIVE_KEYS(ACTIVE_KEYS),.TON_PACK(TON_PACK),
        .TOFF_PACK(TOFF_PACK),.RAW_MIN_PACK(RAW_MIN_PACK),.RAW_MAX_PACK(RAW_MAX_PACK),
        .MIN_GAIN_PACK(MIN_GAIN_PACK)) dut(.*);
    control_frame_receiver receiver(.*);
    integer f,logfile,rc,n=0,reset_in,valid_in,cancel_in,ce_in,valid_expected;
    integer published=0,collisions=0;
    reg [7:0] gate_expected,sample_gate_expected;
    reg [127:0] gain_expected,sample_gain_expected;
    reg [95:0] raw_expected,raw_in;
    initial begin
        f=$fopen("vectors.txt","r"); logfile=$fopen("actual.csv","w");
        if(!f || !logfile) $fatal(1,"Cannot open vectors/log");
        $fdisplay(logfile,"cycle,valid,gate,gain,raw,sample_gate,sample_gain");
        $dumpfile("frames.vcd");
        $dumpvars(0,clk,rst_n,frame_valid,frame_cancel,raw_frame,gate,key_gain,
            controls_valid,control_raw_frame,sample_ce,sample_gate,sample_gain);
        while(!$feof(f)) begin
            rc=$fscanf(f,"%d %d %d %d %h %d %h %h %h %h %h\n",
                reset_in,valid_in,cancel_in,ce_in,raw_in,valid_expected,
                gate_expected,gain_expected,raw_expected,sample_gate_expected,sample_gain_expected);
            if(rc!=11) $fatal(1,"Bad vector %0d rc=%0d",n,rc);
            @(negedge clk);
            rst_n=reset_in; frame_valid=valid_in; frame_cancel=cancel_in;
            sample_ce=ce_in; raw_frame=raw_in;
            @(posedge clk);
            if(rst_n && controls_valid && sample_ce) collisions=collisions+1;
            #1;
            if(controls_valid!==valid_expected[0] || gate!==gate_expected ||
               key_gain!==gain_expected || control_raw_frame!==raw_expected ||
               sample_gate!==sample_gate_expected || sample_gain!==sample_gain_expected)
                $fatal(1,"Frame mismatch cycle=%0d got valid/gate/gain/raw=%b/%h/%h/%h expected=%b/%h/%h/%h sample=%h/%h expected=%h/%h",
                    n,controls_valid,gate,key_gain,control_raw_frame,
                    valid_expected[0],gate_expected,gain_expected,raw_expected,
                    sample_gate,sample_gain,sample_gate_expected,sample_gain_expected);
            if(controls_valid) published=published+1;
            $fdisplay(logfile,"%0d,%0d,%02h,%032h,%024h,%02h,%032h",n,controls_valid,
                gate,key_gain,control_raw_frame,sample_gate,sample_gain);
            n=n+1;
        end
        if(published<8000 || collisions<100) $fatal(1,"Insufficient coverage");
        $display("PASS ALL frames active=%0d cycles=%0d published=%0d old_frame_collisions=%0d",ACTIVE_KEYS,n,published,collisions);
        $fclose(f); $fclose(logfile); $finish;
    end
    initial begin #5000000; $fatal(1,"Frame test timeout"); end
endmodule
`default_nettype wire
