`timescale 1ns/1ps
`default_nettype none
module tb_adc_scan;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    wire cs_n,sclk,mosi,miso,frame_valid,scan_start,scan_busy,timeout;
    wire [95:0] raw_frame;
    wire [31:0] timeout_count;
    reg [95:0] channel_values=0;
    integer dout_delay_ns=200;
    wire [2:0] decoded_channel;
    wire [11:0] selected_value;
    wire [23:0] command_seen;
    wire signed [31:0] model_rises,model_start_edge;
    adc_scan dut(.*);
    mcp3208_model adc(.rst_n(rst_n),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),
        .channel_values(channel_values),.dout_delay_ns(dout_delay_ns),.miso(miso),
        .decoded_channel(decoded_channel),.selected_value(selected_value),
        .command_seen(command_seen),.rise_count(model_rises),.start_edge(model_start_edge));

    integer rounds=0,frames=0,transactions=0,aborted=0,completed=0;
    integer ch=0,rises=0,falls=0,atomic_checks=0,epoch=0;
    integer frame_log,transaction_log;
    reg active=0,round_active=0;
    reg [95:0] expected_frame=0,old_frame=0;
    reg [23:0] tx=0;
    reg [11:0] rx=0;
    time round_start,last_round=0,cs_start,last_cs_end=0,last_edge=0,last_fall=0;
    time frame_pulse=0,scan_pulse=0;
    reg [95:0] previous_publication=0;
    integer active_clock_count=0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) active_clock_count=0;
        else begin
            active_clock_count=active_clock_count+1;
            #1;
            if (scan_start && active_clock_count%50000!=0)
                $fatal(1,"Scan start not on 50,000-clock grid");
        end
    end

    always @(posedge scan_start) begin
        if (!rst_n || round_active || !scan_busy) $fatal(1,"Overlapping round");
        if (last_round && $time-last_round!=1000000) $fatal(1,"Scan period not 1ms");
        rounds=rounds+1; ch=0; completed=0; round_active=1;
        expected_frame=channel_values; old_frame=raw_frame;
        round_start=$time; last_round=$time; scan_pulse=$time;
        $display("SCAN round=%0d epoch=%0d start_ns=%0d clock_count=%0d expected=%024h",rounds,epoch,$time,active_clock_count,expected_frame);
    end
    always @(negedge scan_start)
        if (rst_n && scan_pulse && $time-scan_pulse!=20) $fatal(1,"scan_start width");

    always @(negedge cs_n) begin
        if (rst_n) begin
            if (!round_active || ch>7 || active) $fatal(1,"Unexpected SPI request");
            if (last_cs_end && $time-last_cs_end<2000) $fatal(1,"CS gap <2us");
            active=1; rises=0; falls=0; tx=0; rx=0; last_edge=0; cs_start=$time;
            if (ch==4) begin
                if (raw_frame!==old_frame) $fatal(1,"Partial frame visible at CH4");
                atomic_checks=atomic_checks+1;
                $display("PASS atomic_CH4 round=%0d old_frame=%024h",rounds,raw_frame);
            end
        end
    end
    always @(sclk) begin
        if (rst_n && sclk && cs_n) $fatal(1,"SCLK outside CS");
        if (rst_n && active) begin
            if (last_edge && $time-last_edge!=1000) $fatal(1,"SPI half-cycle");
            last_edge=$time;
            if (sclk) begin
                rises=rises+1; tx={tx[22:0],mosi};
                if (rises==1 && $time-cs_start!=1000) $fatal(1,"CS setup");
                if (rises<=11 && miso!==1'bx) $fatal(1,"Unknown prefix");
                if (rises==12 && miso!==0) $fatal(1,"Null");
                if (rises>=13) rx={rx[10:0],miso};
            end else begin falls=falls+1; last_fall=$time; end
        end
    end
    always @(posedge cs_n) begin
        if (active) begin
            transactions=transactions+1;
            if (rst_n) begin
                if (rises!=24 || falls!=24 || sclk || $time-last_fall!=1000)
                    $fatal(1,"Incomplete SPI transaction");
                if (tx!==(24'h060000 | (ch<<14)) || decoded_channel!==ch[2:0] || model_start_edge!=6)
                    $fatal(1,"Channel/command mismatch ch=%0d tx=%h",ch,tx);
                if (rx!==expected_frame[12*ch+:12] || selected_value!==rx)
                    $fatal(1,"Channel payload mismatch");
                $fdisplay(transaction_log,"%0d,%0d,%0d,normal,%0d,%0d,%0d,%0d,%06h,%03h",
                    transactions,rounds,ch,cs_start,$time,rises,falls,tx,rx);
                completed=completed+1; ch=ch+1;
            end else begin
                aborted=aborted+1;
                $fdisplay(transaction_log,"%0d,%0d,%0d,reset_abort,%0d,%0d,%0d,%0d,%06h,---",
                    transactions,rounds,ch,cs_start,$time,rises,falls,tx);
            end
            last_cs_end=$time; active=0;
        end
    end
    always @(raw_frame) begin
        #1;
        if (rst_n && !frame_valid) $fatal(1,"raw_frame changed without valid");
    end
    always @(posedge frame_valid) begin
        frame_pulse=$time;
        if (!rst_n || !round_active || scan_busy || completed!=8 || raw_frame!==expected_frame)
            $fatal(1,"Frame publication failed got=%024h expected=%024h",raw_frame,expected_frame);
        if ($time-round_start>=1000000) $fatal(1,"Scan exceeded deadline");
        frames=frames+1; round_active=0; previous_publication=raw_frame;
        $fdisplay(frame_log,"%0d,%0d,%0d,%0d,%0d,%0d,%024h,%024h",frames,rounds,epoch,
            round_start,$time,$time-round_start,raw_frame,expected_frame);
        $display("PASS frame=%0d round=%0d latency_ns=%0d raw=%024h",frames,rounds,$time-round_start,raw_frame);
    end
    always @(negedge frame_valid)
        if (rst_n && frame_pulse && $time-frame_pulse!=20) $fatal(1,"frame_valid width");
    always @(posedge timeout) $fatal(1,"Unexpected normal-link timeout");
    always @(negedge rst_n) begin
        #2;
        if (raw_frame!==0 || frame_valid || scan_busy || timeout || timeout_count!==0 || !cs_n || sclk)
            $fatal(1,"Reset did not clear partial frame/outputs");
        round_active=0; last_round=0; epoch=epoch+1;
        $display("PASS reset_discard_partial frame_count=%0d",frames);
    end
    task set_bank(input integer base);
        integer k;
        begin for(k=0;k<8;k=k+1) channel_values[12*k+:12]=base+100*k; end
    endtask
    initial begin
        frame_log=$fopen("frames.csv","w"); transaction_log=$fopen("transactions.csv","w");
        if (!frame_log || !transaction_log) $fatal(1,"Cannot open evidence");
        $fdisplay(frame_log,"frame,round,epoch,start_ns,publish_ns,duration_ns,raw_frame,expected_frame");
        $fdisplay(transaction_log,"transaction,round,channel,status,start_ns,end_ns,rises,falls,command,payload");
        $dumpfile("scan.vcd");
        $dumpvars(0,rst_n,cs_n,sclk,mosi,miso,raw_frame,frame_valid,scan_start,scan_busy,timeout,timeout_count,channel_values);
        channel_values={12'h001,12'h800,12'hAAA,12'h555,12'hFFF,12'hABC,12'h001,12'h000};
        repeat(5) @(negedge clk); rst_n=1;
        wait(frames==1); @(negedge clk); set_bank(100);
        wait(frames==3); // Two identical input frames must still each publish.
        @(negedge clk); set_bank(1100);
        wait(frames==4);
        wait(active && ch==4 && rises==7); #17; rst_n=0;
        #20; rst_n=1; set_bank(2100);
        wait(frames==6);
        repeat(4) @(negedge clk);
        if (rounds!=7 || transactions!=53 || aborted!=1 || atomic_checks!=7 || timeout_count!==0)
            $fatal(1,"Final integrated counts wrong");
        $display("PASS ALL integrated frames=6 rounds=7 transactions=53 aborted=1 atomic_CH4=7 timeout_count=0");
        $fclose(frame_log); $fclose(transaction_log); $finish;
    end
    initial begin #12000000; $fatal(1,"Integrated test timeout"); end
endmodule
`default_nettype wire
