`timescale 1ns/1ps
module tb_input_examples;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    wire miso,cs_n,sclk,mosi,cv,rv,miss;
    wire [7:0] gate,fg;
    wire [127:0] gain,fk;
    wire [11:0] raw;
    wire fv;
    reg [95:0] values=0;
    wire [2:0] decoded_channel;
    wire [11:0] selected_value;
    wire [23:0] command_seen;
    integer rise_count,start_edge;
    pressure_ch0_input dut(.clk(clk),.rst_n(rst_n),.miso(miso),.cs_n(cs_n),
        .sclk(sclk),.mosi(mosi),.gate(gate),.key_gain(gain),.controls_valid(cv),
        .raw_data(raw),.raw_valid(rv),.missed_tick(miss));
    mcp3208_model model(.rst_n(rst_n),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),
        .channel_values(values),.dout_delay_ns(200),.miso(miso),
        .decoded_channel(decoded_channel),.selected_value(selected_value),
        .command_seen(command_seen),.rise_count(rise_count),.start_edge(start_edge));
    fake_ch0_controls #(.FRAME_CYCLES(8),.STAGE_FRAMES(2)) fake(
        .clk(clk),.rst_n(rst_n),.gate(fg),.key_gain(fk),.controls_valid(fv));
    integer cycle=0,fakes=0,frames=0,last_frame=0,expected_stage;
    reg prev_cv=0,prev_rv=0;
    reg [7:0] old_gate=0;
    reg [127:0] old_gain=0;
    always @(posedge clk) begin
        if(rst_n) begin
            cycle=cycle+1;
            #1;
            if(miss!==0 || gate[7:1]!==0 || gain[127:16]!==0)
                $fatal(1,"Diagnostics or packing mismatch");
            if(cv!==prev_rv || (cv && prev_cv)) $fatal(1,"valid alignment/width");
            if(!cv && (gate!==old_gate || gain!==old_gain)) $fatal(1,"frame not held");
            if(cv) begin
                frames=frames+1;
                if(frames>1 && cycle-last_frame!=50000) $fatal(1,"Not 1ms control period");
                last_frame=cycle;
                if(command_seen!==24'h060000 || rise_count!=24 || decoded_channel!==0)
                    $fatal(1,"External SPI decode mismatch");
                case(frames)
                    1,2: if(gate!==0 || gain!==0 || raw!==0) $fatal(1,"initial silence");
                    3: if(gate!==0 || gain!==0 || raw!==256) $fatal(1,"first confirmation");
                    4: if(gate!==1 || gain!==4626 || raw!==256) $fatal(1,"second confirmation");
                    5,6,7: if(gate!==1 || gain<=old_gain || raw!==4095) $fatal(1,"held gain rise");
                    8: if(gate!==1 || gain==0 || raw!==0) $fatal(1,"first release confirmation");
                    9: if(gate!==0 || gain!==0 || raw!==0) $fatal(1,"release");
                endcase
                if(frames==2) values[11:0]=256;
                if(frames==4) values[11:0]=4095;
                if(frames==7) values[11:0]=0;
            end
            if(fv) begin
                expected_stage=(fakes/2)%4;
                if(cycle%8!=0) $fatal(1,"fake period");
                if(fg!==(expected_stage==1 || expected_stage==2 ? 8'd1 : 8'd0)
                    || fk!== (expected_stage==1 ? 128'h4000 : expected_stage==2 ? 128'hc000 : 128'd0))
                    $fatal(1,"fake control sequence");
                fakes=fakes+1;
            end
            prev_rv=rv; prev_cv=cv; old_gate=gate; old_gain=gain;
        end else begin
            #1;
            if(gate!==0 || gain!==0 || cv!==0 || fg!==0 || fk!==0 || fv!==0)
                $fatal(1,"reset silence");
            cycle=0; frames=0; fakes=0; prev_rv=0; prev_cv=0; old_gate=0; old_gain=0;
        end
    end
    initial begin
        $dumpfile("examples.vcd"); $dumpvars(1,tb_input_examples);
        repeat(4) @(negedge clk); rst_n=1;
        wait(frames==9); @(negedge clk); rst_n=0;
        repeat(4) @(negedge clk);
        $display("PASS ALL examples: real CH0 SPI/1ms/controls and fake source/reset"); $finish;
    end
    initial begin #12000000; $fatal(1,"watchdog"); end
endmodule
