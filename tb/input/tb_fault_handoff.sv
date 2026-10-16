`timescale 1ns/1ps
`default_nettype none
// Inject faults at the PUBLIC controller handshake, never force DUT internals.
module tb_fault_handoff;
    reg clk=0,rst_n=0,spi_busy=0,spi_valid=0;
    reg [11:0] spi_data=0;
    always #10 clk=~clk;
    wire spi_start,spi_abort,frame_valid,scan_start,scan_busy,timeout,controls_valid;
    wire [2:0] spi_channel;
    wire [95:0] raw_frame,control_raw_frame;
    wire [31:0] timeout_count;
    wire [7:0] gate;
    wire [127:0] key_gain;
    adc_scan_controller scanner(.*);
    pressure_frame_controls controls(.clk(clk),.rst_n(rst_n),.raw_frame(raw_frame),
        .frame_valid(frame_valid),.frame_cancel(timeout),.gate(gate),.key_gain(key_gain),
        .controls_valid(controls_valid),.control_raw_frame(control_raw_frame));
    integer frames=0,errors=0,k,rounds=0;
    time start_time=0;
    reg [95:0] bank=0;
    reg [7:0] saved_gate=0;
    reg [127:0] saved_gain=0;
    always @(posedge scan_start) begin rounds=rounds+1; start_time=$time; end
    always @(posedge controls_valid) frames=frames+1;
    always @(posedge timeout) begin
        errors=errors+1;
        #1;
        if(gate!==saved_gate || key_gain!==saved_gain || controls_valid ||
           timeout_count!==errors || frame_valid || !spi_abort) $fatal(1,"Fault changed held controls");
    end
    task reply(input integer ch);
        begin
            @(posedge spi_start);
            if(spi_channel!==ch[2:0]) $fatal(1,"Wrong request channel");
            @(negedge clk); spi_busy=1;
            repeat(5) @(negedge clk);
            spi_data=bank[12*ch+:12]; spi_busy=0; spi_valid=1;
            @(negedge clk); spi_valid=0;
        end
    endtask
    task good(input [7:0] expected_gate);
        begin
            @(posedge scan_start);
            for(integer c=0;c<8;c=c+1) reply(c);
            @(posedge controls_valid); #1;
            if(gate!==expected_gate || control_raw_frame!==bank) $fatal(1,"Confirmation after fault gate=%h expected=%h",gate,expected_gate);
            saved_gate=gate; saved_gain=key_gain;
        end
    endtask
    task abort_done;
        begin
            @(negedge clk); spi_busy=0; spi_valid=0;
            repeat(25) @(negedge clk);
            if(controls_valid || gate!==saved_gate || key_gain!==saved_gain) $fatal(1,"Late fault publication");
        end
    endtask
    initial begin
        $dumpfile("handoff.vcd");
        $dumpvars(0,rst_n,spi_start,spi_channel,spi_busy,spi_valid,spi_data,spi_abort,
            raw_frame,frame_valid,scan_start,timeout,timeout_count,gate,key_gain,controls_valid);
        repeat(5) @(negedge clk); rst_n=1; bank={8{12'd3000}};
        good(8'h00); // First press confirmation.
        @(posedge scan_start);
        for(k=0;k<3;k=k+1) reply(k);
        @(posedge spi_start); @(negedge clk); spi_busy=1;
        @(posedge timeout); abort_done();
        good(8'h00); // Missing round breaks consecutive confirmations.
        good(8'h0f);
        bank=0; good(8'h0f); // First release confirmation.
        @(posedge scan_start);
        for(k=0;k<7;k=k+1) reply(k);
        @(posedge spi_start); @(negedge clk); spi_busy=1;
        #(start_time+1000000-$time-10);
        spi_data=0; spi_busy=0; spi_valid=1; // CH7 exactly at deadline loses.
        @(posedge timeout); abort_done();
        good(8'h0f);
        good(8'h00);
        if(key_gain!==0 || frames!=6 || errors!=2 || rounds!=8) $fatal(1,"Fault final counts");
        $display("PASS ALL fault_handoff frames=6 timeouts=2 missing_CH3=1 deadline_CH7=1 confirmations_cleared=2");
        $finish;
    end
    initial begin #12000000; $fatal(1,"Fault handoff timeout"); end
endmodule
`default_nettype wire
