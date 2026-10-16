`timescale 1ns/1ps
`default_nettype none
// Unit fault injection at the controller's documented SPI handshake ports.
// No force/release or DUT internal state references; not a physical ADC model.
module tb_scan_faults;
    reg clk=0,rst_n=0,spi_busy=0,spi_valid=0;
    reg [11:0] spi_data=0;
    always #10 clk=~clk;
    wire spi_start,spi_abort,frame_valid,scan_start,scan_busy,timeout;
    wire [2:0] spi_channel;
    wire [95:0] raw_frame;
    wire [31:0] timeout_count;
    adc_scan_controller dut(.*);
    reg [95:0] expected=0,held_frame=0;
    integer frames=0,rounds=0,errors=0,requests=0,channel_cursor=0;
    integer log_file,k,before_requests;
    time round_start=0,last_round=0,pulse_start=0,request_time=0,error_time=0;
    reg active=0;

    task bank(input integer base);
        integer n;
        begin for(n=0;n<8;n=n+1) expected[12*n+:12]=base+17*n; end
    endtask
    always @(posedge scan_start) begin
        if (active || !scan_busy || frame_valid) $fatal(1,"Fault test overlap");
        rounds=rounds+1; active=1; channel_cursor=0;
        round_start=$time;
        if (last_round && ($time-last_round!=1000000 && $time-last_round!=2000000))
            $fatal(1,"Scheduler drifted off periodic grid");
        last_round=$time;
        $fdisplay(log_file,"SCAN,%0d,%0d,%0d,%024h",$time,rounds,timeout_count,raw_frame);
    end
    always @(posedge spi_start) begin
        if (!active || spi_channel!==channel_cursor[2:0] || spi_busy)
            $fatal(1,"Wrong request/order or busy overlap");
        channel_cursor=channel_cursor+1; requests=requests+1; request_time=$time;
        $fdisplay(log_file,"REQUEST,%0d,%0d,%0d,%024h",$time,rounds,spi_channel,raw_frame);
    end
    always @(negedge spi_start)
        if (rst_n && request_time && $time-request_time!=20) $fatal(1,"spi_start width");
    always @(posedge frame_valid) begin
        pulse_start=$time;
        if (!active || scan_busy || channel_cursor!=8 || raw_frame!==expected || timeout || spi_abort)
            $fatal(1,"Fault recovery frame mismatch");
        active=0; frames=frames+1;
        $fdisplay(log_file,"FRAME,%0d,%0d,%0d,%024h",$time,rounds,timeout_count,raw_frame);
    end
    always @(negedge frame_valid)
        if (rst_n && pulse_start && $time-pulse_start!=20) $fatal(1,"frame_valid width");
    always @(posedge timeout) begin
        errors=errors+1; error_time=$time;
        if (!active || scan_busy || scan_start || frame_valid || spi_start || !spi_abort ||
            timeout_count!==errors || raw_frame!==held_frame || $time-round_start!=1000000)
            $fatal(1,"Timeout did not cancel exactly at the next tick");
        active=0;
        $fdisplay(log_file,"TIMEOUT,%0d,%0d,%0d,%024h",$time,rounds,timeout_count,raw_frame);
    end
    always @(negedge timeout)
        if (rst_n && error_time && $time-error_time!=20) $fatal(1,"timeout width");
    always @(raw_frame) begin
        #1;
        if (rst_n && !frame_valid) $fatal(1,"Partial/timeout frame leaked");
    end

    task reply(input integer ch);
        begin
            @(posedge spi_start);
            if (spi_channel!==ch[2:0]) $fatal(1,"Reply wrong channel");
            @(negedge clk); spi_busy=1;
            repeat(5) @(negedge clk);
            spi_data=expected[12*ch+:12]; spi_busy=0; spi_valid=1;
            @(negedge clk); spi_valid=0;
        end
    endtask
    task good_round;
        integer n;
        begin
            @(posedge scan_start);
            for(n=0;n<8;n=n+1) reply(n);
            if (raw_frame!==expected || frame_valid!==1) $fatal(1,"Good round not published");
            repeat(2) @(negedge clk);
            held_frame=raw_frame;
        end
    endtask
    task check_abort_done;
        begin
            @(negedge clk); spi_busy=0; spi_valid=0;
            repeat(3) @(negedge clk);
            if (timeout || spi_abort || scan_busy || frame_valid || raw_frame!==held_frame)
                $fatal(1,"Abort pulse did not clear/last frame not held");
        end
    endtask
    initial begin
        log_file=$fopen("fault_events.csv","w");
        if (!log_file) $fatal(1,"Cannot open fault log");
        $fdisplay(log_file,"event,time_ns,round,channel_or_timeout_count,raw_frame");
        $dumpfile("faults.vcd");
        $dumpvars(0,rst_n,spi_busy,spi_valid,spi_data,spi_start,spi_channel,spi_abort,
            raw_frame,frame_valid,scan_start,scan_busy,timeout,timeout_count);
        repeat(5) @(negedge clk); rst_n=1; bank(100);
        good_round();
        $display("PASS baseline_raw=%024h",held_frame);

        bank(500);
        @(posedge scan_start);
        for(k=0;k<3;k=k+1) reply(k);
        @(posedge spi_start); @(negedge clk); spi_busy=1; // Drop CH3 response.
        @(posedge timeout); #2;
        if (frames!=1 || requests!=12) $fatal(1,"Missing-result accounting");
        check_abort_done();
        // A late response in IDLE must not publish the abandoned half-frame.
        spi_data=12'hBAD; spi_valid=1;
        @(negedge clk); spi_valid=0;
        repeat(5) @(negedge clk);
        if (frames!=1 || raw_frame!==held_frame) $fatal(1,"Late response published");
        $display("PASS missing_CH3 timeout_count=1 late_valid_ignored=1 last_frame_held=1");
        bank(900); good_round();
        $display("PASS recovery_after_missing_result frame=%024h",raw_frame);

        before_requests=requests;
        spi_busy=1; // Never ready even for CH0.
        @(posedge scan_start); @(posedge timeout); #2;
        if (requests!=before_requests || frames!=2) $fatal(1,"Issued while SPI busy");
        check_abort_done();
        $display("PASS never_ready timeout_count=2 issued_requests=0 last_frame_held=1");
        bank(1300); good_round();

        bank(1700);
        @(posedge scan_start);
        for(k=0;k<7;k=k+1) reply(k);
        @(posedge spi_start); @(negedge clk); spi_busy=1;
        // Present CH7 valid at precisely the next scan-deadline sampling edge.
        #(round_start+1000000-$time-10);
        spi_data=expected[84+:12]; spi_busy=0; spi_valid=1;
        @(posedge timeout); #2;
        if (frames!=3 || raw_frame!==held_frame) $fatal(1,"Deadline CH7 should be discarded");
        check_abort_done();
        $display("PASS CH7_at_deadline timeout_count=3 frame_valid=0 last_frame_held=1");
        bank(2100); good_round();
        if (frames!=4 || errors!=3 || rounds!=7 || timeout_count!==3)
            $fatal(1,"Final fault counts");
        $display("PASS ALL faults rounds=7 published=4 timeouts=3 recovery=3");
        $fclose(log_file); $finish;
    end
    initial begin #12000000; $fatal(1,"Fault test timeout"); end
endmodule
`default_nettype wire
