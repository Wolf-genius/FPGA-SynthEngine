`timescale 1ns/1ps
`default_nettype none
module tb_scan_controls;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    wire cs_n,sclk,mosi,miso,frame_valid,scan_start,scan_busy,timeout,controls_valid;
    wire [95:0] raw_frame,control_raw_frame;
    wire [7:0] gate;
    wire [127:0] key_gain;
    wire [31:0] timeout_count;
    reg [95:0] channel_values=0;
    integer dout_delay_ns=200;
    wire [2:0] decoded_channel;
    wire [11:0] selected_value;
    wire [23:0] command_seen;
    wire signed [31:0] model_rises,model_start_edge;
    pressure_keys_input dut(.*);
    mcp3208_model adc(.rst_n(rst_n),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),
        .channel_values(channel_values),.dout_delay_ns(dout_delay_ns),.miso(miso),
        .decoded_channel(decoded_channel),.selected_value(selected_value),
        .command_seen(command_seen),.rise_count(model_rises),.start_edge(model_start_edge));
    integer rounds=0,frames=0,controls=0,ch=0,rises=0,falls=0,transactions=0,aborts=0,atomic_checks=0;
    integer logfile,epoch=0,cycle=0,pending_cycle=-1;
    reg active=0;
    reg [95:0] expected=0;
    reg [7:0] held_gate=0;
    reg [127:0] held_gain=0;
    reg [23:0] tx;
    reg [11:0] rx;
    time last_start=0,round_start=0,last_edge=0,last_end=0,cs_start=0,last_fall=0;
    time last_mosi=0,last_rise=0,pulse=0;
    always @(posedge clk) cycle=cycle+1;
    always @(posedge scan_start) begin
        if(last_start && $time-last_start!=1000000) $fatal(1,"Not 1ms scan");
        last_start=$time; round_start=$time; rounds=rounds+1; ch=0;
        // Directed real-pin ADC stimuli, fixed for an entire scan.
        case(rounds)
            1: channel_values={4{24'hfff000}};
            2,3: channel_values={12'hfff,12'haaa,12'h555,12'habc,12'd3200,12'd2400,12'd1600,12'd800};
            4,5: channel_values={12'hfff,12'hfff,12'hfff,12'hfff,12'd3200,12'd2400,12'd0,12'd800};
            6,7: channel_values={12'hfff,12'hfff,12'hfff,12'hfff,12'd3200,12'd400,12'd1600,12'd800};
            8,9: channel_values={12'hfff,12'hfff,12'hfff,12'hfff,12'd3200,12'd3600,12'd1600,12'd800};
            10,11: channel_values=0;
            default: channel_values={8{12'd3000}};
        endcase
        expected=channel_values; held_gate=gate; held_gain=key_gain;
        $fdisplay(logfile,"SCAN,%0d,%0d,%0d,%024h,%02h,%032h",epoch,cycle,$time,expected,gate,key_gain);
    end
    always @(mosi) begin
        if(rst_n && active && (sclk || (last_rise && $time-last_rise<50)))
            $fatal(1,"MOSI hold/edge");
        last_mosi=$time;
    end
    always @(negedge cs_n) if(rst_n) begin
        if(active || ch>7 || (last_end && $time-last_end<2000)) $fatal(1,"CS overlap/gap");
        active=1; rises=0; falls=0; tx=0; rx=0; cs_start=$time; last_edge=0; last_rise=0;
        if(ch==4) begin
            if(gate!==held_gate || key_gain!==held_gain) $fatal(1,"Partial controls visible at CH4");
            atomic_checks=atomic_checks+1;
        end
    end
    always @(sclk) if(rst_n && active) begin
        if(last_edge && $time-last_edge!=1000) $fatal(1,"SPI half period");
        last_edge=$time;
        if(sclk) begin
            rises=rises+1; tx={tx[22:0],mosi}; last_rise=$time;
            if($time-last_mosi<50 || (rises==1 && $time-cs_start!=1000)) $fatal(1,"SPI setup");
            if(rises<=11 && miso!==1'bx) $fatal(1,"Unknown prefix missing");
            if(rises==12 && miso!==1'b0) $fatal(1,"Null missing");
            if(rises>=13) rx={rx[10:0],miso};
        end else begin falls=falls+1; last_fall=$time; end
    end
    always @(posedge cs_n) if(active) begin
        if(rst_n) begin
            if(rises!=24 || falls!=24 || sclk || $time-last_fall!=1000 ||
                tx!==(24'h060000 | ({21'd0,ch[2:0]}<<14)) || decoded_channel!==ch[2:0] ||
                model_start_edge!=6 || rx!==expected[12*ch+:12]) $fatal(1,"SPI command/data/timing");
            ch=ch+1; transactions=transactions+1;
        end else aborts=aborts+1;
        last_end=$time; active=0;
    end
    always @(posedge frame_valid) begin
        if(ch!=8 || raw_frame!==expected || $time-round_start>=1000000) $fatal(1,"Raw frame mismatch");
        frames=frames+1; pending_cycle=cycle;
        $fdisplay(logfile,"RAW,%0d,%0d,%0d,%024h,%02h,%032h",epoch,cycle,$time,raw_frame,gate,key_gain);
    end
    always @(posedge controls_valid) begin
        if(cycle-pending_cycle!=20 || control_raw_frame!==expected || gate[7:4]!==0 || key_gain[127:64]!==0)
            $fatal(1,"Control frame latency/packing");
        controls=controls+1; pulse=$time;
        $fdisplay(logfile,"CONTROL,%0d,%0d,%0d,%024h,%02h,%032h",epoch,cycle,$time,control_raw_frame,gate,key_gain);
    end
    always @(negedge controls_valid) if(rst_n && pulse && $time-pulse!=20) $fatal(1,"valid pulse width");
    always @(gate,key_gain,control_raw_frame) begin
        #1;
        if(rst_n && !controls_valid) $fatal(1,"Control changed without valid");
    end
    always @(posedge timeout) $fatal(1,"Unexpected scan timeout");
    initial begin
        logfile=$fopen("integrated.csv","w");
        $fdisplay(logfile,"event,epoch,cycle,time_ns,raw,gate,gain");
        $dumpfile("integrated.vcd");
        $dumpvars(0,rst_n,cs_n,sclk,mosi,miso,channel_values,raw_frame,frame_valid,
            scan_start,scan_busy,timeout,timeout_count,gate,key_gain,controls_valid,control_raw_frame);
        repeat(5) @(negedge clk); rst_n=1;
        wait(controls==11);
        // Reset in the next scan CH4. No half-frame or phantom controls.
        wait(active && ch==4 && rises==7); #3; rst_n=0; epoch=1; last_start=0; pending_cycle=-1;
        #1; if(gate!==0 || key_gain!==0 || controls_valid || control_raw_frame!==0) $fatal(1,"Reset not silent");
        #20; rst_n=1;
        wait(controls==14); repeat(5) @(negedge clk);
        if(controls!=frames || aborts!=1 || timeout_count!=0 || atomic_checks!=15)
            $fatal(1,"Integrated final counts");
        $display("PASS ALL scan_controls frames=%0d controls=%0d transactions=%0d reset_aborts=%0d atomic_CH4=%0d",frames,controls,transactions,aborts,atomic_checks);
        $fclose(logfile); $finish;
    end
    initial begin #20000000; $fatal(1,"Integration timeout"); end
endmodule
`default_nettype wire
