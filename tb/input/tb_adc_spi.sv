`timescale 1ns/1ps
`default_nettype none
module tb_adc_spi;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, start = 0;
    reg [2:0] channel = 0;
    wire miso, cs_n, sclk, mosi, busy, valid;
    wire [11:0] data;
    reg [95:0] channel_values = 0;
    integer dout_delay_ns = 200;
    wire [2:0] decoded_channel;
    wire [11:0] selected_value;
    wire [23:0] command_seen;
    wire signed [31:0] model_rises, model_start_edge;

    adc_spi dut (.clk(clk), .rst_n(rst_n), .start(start),
        .channel(channel), .miso(miso), .cs_n(cs_n), .sclk(sclk),
        .mosi(mosi), .busy(busy), .data(data), .valid(valid));
    mcp3208_model adc (.rst_n(rst_n), .cs_n(cs_n), .sclk(sclk),
        .mosi(mosi), .channel_values(channel_values),
        .dout_delay_ns(dout_delay_ns), .miso(miso),
        .decoded_channel(decoded_channel), .selected_value(selected_value),
        .command_seen(command_seen), .rise_count(model_rises),
        .start_edge(model_start_edge));

    integer valid_count = 0, normal_count = 0, abort_count = 0;
    integer frame_id = 0, rises = 0, falls = 0, i, j;
    integer frames_file, events_file;
    reg active = 0, previous_valid = 0, pending = 0;
    reg [11:0] previous_data = 0;
    reg [23:0] tx_seen = 0;
    reg [11:0] rx_seen = 0, expected_data = 0;
    reg [2:0] expected_channel = 0;
    string case_name = "initial";
    time cs_start, last_cs_end = 0, last_edge = 0, last_fall = 0;
    time last_rise = 0, last_mosi_change = 0, valid_start;
    time frame_gap, min_setup, min_hold;
    time reset_released = 0;

    // These checkers inspect pins/outputs only, never DUT internal state.
    always @(sclk)
        if (rst_n && cs_n && sclk !== 1'b0)
            $fatal(1, "SCLK toggled high while CS inactive");

    always @(mosi) begin
        if (rst_n && active) begin
            if (sclk !== 1'b0)
                $fatal(1, "MOSI changed with SCLK high");
            if (last_rise != 0 && $time-last_rise < 50)
                $fatal(1, "MOSI hold below 50ns");
            if (last_rise != 0 && $time-last_rise < min_hold)
                min_hold = $time-last_rise;
        end
        last_mosi_change = $time;
    end

    always @(negedge cs_n) begin
        if (rst_n) begin
            if (sclk !== 1'b0 || busy !== 1'b1)
                $fatal(1, "Bad accepted-request outputs");
            frame_gap = last_cs_end == 0 ? 0 : $time-last_cs_end;
            if (last_cs_end != 0 && frame_gap < 2000)
                $fatal(1, "CS high gap below 2000ns: %0d", frame_gap);
            if ($time-reset_released < 2000)
                $fatal(1, "Reset recovery CS guard too short");
            frame_id = frame_id+1;
            active = 1;
            cs_start = $time;
            rises = 0; falls = 0; tx_seen = 0; rx_seen = 0;
            last_edge = 0; last_fall = 0; last_rise = 0;
            min_setup = 1000000; min_hold = 1000000;
            $fdisplay(events_file, "ACCEPT,%0d,%0d,%s,ch=%0d",
                      frame_id, $time, case_name, expected_channel);
        end
    end

    always @(posedge sclk) begin
        if (rst_n && active) begin
            if (cs_n !== 1'b0) $fatal(1, "Clock outside CS");
            if (last_edge != 0 && $time-last_edge != 1000)
                $fatal(1, "SCLK low half-cycle not 1000ns");
            if (rises == 0 && $time-cs_start != 1000)
                $fatal(1, "CS setup not 1000ns");
            if ($time-last_mosi_change < 50)
                $fatal(1, "MOSI setup below 50ns");
            if ($time-last_mosi_change < min_setup)
                min_setup = $time-last_mosi_change;
            last_edge = $time;
            last_rise = $time;
            rises = rises+1;
            if (rises > 24) $fatal(1, "More than 24 rising edges");
            tx_seen = {tx_seen[22:0], mosi};
            if (rises <= 11 && miso !== 1'bx)
                $fatal(1, "Model prefix should be unknown");
            if (rises == 12 && miso !== 1'b0)
                $fatal(1, "Null bit not zero");
            if (rises >= 13) begin
                if (miso !== expected_data[24-rises])
                    $fatal(1, "MISO bit mismatch at rising edge %0d", rises);
                rx_seen = {rx_seen[10:0], miso};
            end
            $fdisplay(events_file, "RISE,%0d,%0d,%s,edge=%0d mosi=%b miso=%b",
                      frame_id, $time, case_name, rises, mosi, miso);
        end
    end

    always @(negedge sclk) begin
        if (rst_n && active) begin
            if ($time-last_edge != 1000)
                $fatal(1, "SCLK high half-cycle not 1000ns");
            falls = falls+1;
            last_edge = $time;
            last_fall = $time;
        end
    end

    always @(posedge cs_n) begin
        if (active) begin
            if (rst_n) begin
                if (rises != 24 || falls != 24 || sclk !== 1'b0)
                    $fatal(1, "Frame incomplete rises=%0d falls=%0d", rises, falls);
                if (tx_seen !== (24'h060000 | ({21'd0,expected_channel} << 14)))
                    $fatal(1, "Command mismatch: %h", tx_seen);
                if (model_start_edge != 6 || decoded_channel !== expected_channel ||
                    command_seen !== tx_seen || selected_value !== expected_data)
                    $fatal(1, "Independent model decode mismatch");
                if (rx_seen !== expected_data)
                    $fatal(1, "Raw MISO payload mismatch");
                if ($time-last_fall != 1000)
                    $fatal(1, "CS final hold not 1000ns");
                normal_count = normal_count+1;
                $fdisplay(frames_file, "%0d,%s,normal,%0d,%0d,%0d,%0d,%0d,%06h,%0d,%03h,%0d,%0d,%0d,%0d",
                    frame_id, case_name, cs_start, $time, frame_gap, rises, falls,
                    tx_seen, decoded_channel, rx_seen, min_setup, min_hold,
                    $time-last_fall, dout_delay_ns);
            end else begin
                abort_count = abort_count+1;
                $fdisplay(frames_file, "%0d,%s,reset_abort,%0d,%0d,%0d,%0d,%0d,%06h,-1,---,0,0,0,%0d",
                    frame_id, case_name, cs_start, $time, frame_gap, rises, falls,
                    tx_seen, dout_delay_ns);
            end
            last_cs_end = $time;
            active = 0;
        end
    end

    always @(negedge rst_n) begin
        #1;
        if (cs_n !== 1 || sclk !== 0 || mosi !== 0 || busy !== 0 ||
            valid !== 0 || data !== 0)
            $fatal(1, "Asynchronous reset outputs incorrect");
        // A short async reset may contain no posedge clk at all.
        previous_data = 0;
        previous_valid = 0;
        pending = 0;
    end

    always @(posedge rst_n) reset_released = $time;

    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            previous_valid = 0;
            previous_data = 0;
            pending = 0;
        end else begin
            if (start && !pending && busy) pending = 1;
            if (pending && !valid && !busy)
                $fatal(1, "busy cleared before valid");
            if (valid && previous_valid) $fatal(1, "valid exceeds one cycle");
            if (data !== previous_data && !valid)
                $fatal(1, "data changed without valid");
            if (!busy && (cs_n !== 1 || sclk !== 0 || mosi !== 0))
                $fatal(1, "Idle outputs incorrect");
            if (valid) begin
                if (busy !== 0 || cs_n !== 1 || sclk !== 0 || data !== expected_data)
                    $fatal(1, "Published data/control mismatch expected=%h got=%h",
                              expected_data, data);
                if (normal_count != valid_count+1)
                    $fatal(1, "Not exactly one completed frame per valid");
                valid_count = valid_count+1;
                pending = 0;
                $fdisplay(events_file, "VALID,%0d,%0d,%s,data=%03h busy=%b cs_n=%b sclk=%b",
                          frame_id, $time-1, case_name, data, busy, cs_n, sclk);
            end
            previous_valid = valid;
            previous_data = data;
        end
    end

    always @(posedge valid) valid_start = $time;
    always @(negedge valid)
        if (rst_n && valid_start != 0 && $time-valid_start != 20)
            $fatal(1, "valid pulse width not 20ns");

    task launch(input [2:0] ch, input string name);
        begin
            @(negedge clk);
            if (busy) $fatal(1, "Test requested while busy");
            case_name = name;
            expected_channel = ch;
            expected_data = channel_values[12*ch +: 12];
            channel = ch;
            start = 1;
            @(negedge clk);
            start = 0;
            wait (cs_n === 1'b0); // An early reset-recovery request may wait.
        end
    endtask

    task await_result(input integer before_valid);
        begin
            wait (valid === 1'b1);
            #2;
            if (valid_count != before_valid+1 || data !== expected_data)
                $fatal(1, "Missing, duplicate or incorrect result");
            repeat (4) @(negedge clk);
            $display("PASS CASE=%s ch=%0d command=%06h data=%03h tDO_ns=%0d valid_count=%0d",
                     case_name, expected_channel, tx_seen, data, dout_delay_ns, valid_count);
        end
    endtask

    task read_one(input [2:0] ch, input string name);
        integer before_valid;
        begin
            before_valid = valid_count;
            launch(ch, name);
            await_result(before_valid);
        end
    endtask

    task quiet_check(input integer expected_count);
        begin
            repeat (2700) @(negedge clk); // Longer than a complete transaction.
            if (valid_count != expected_count || busy || !cs_n || sclk)
                $fatal(1, "Unexpected queued transfer or idle corruption");
        end
    endtask

    task reset_in_phase(input integer phase_id, input string name);
        integer before_valid;
        begin
            before_valid = valid_count;
            launch(3'd4, name);
            case (phase_id)
                0: #100; // CS setup, before the first SCLK edge.
                1: begin wait (rises == 8); #100; end // Command phase.
                2: begin wait (rises == 18); #100; end // Payload phase.
                3: begin wait (falls == 24); #100; end // Final CS-low hold.
                4: begin @(posedge cs_n); #100; end // CS-high gap, still busy.
            endcase
            rst_n = 0;
            #2;
            if (data !== 0 || busy || valid || !cs_n || sclk || mosi)
                $fatal(1, "Reset phase %0d failed", phase_id);
            repeat (5) @(negedge clk);
            rst_n = 1;
            quiet_check(before_valid);
            // GAP reset canceled publication of an already completed SPI frame.
            if (phase_id == 4) normal_count = normal_count-1;
            $display("PASS CASE=%s canceled_valid=0 reset_data=000", name);
            read_one(3'd5, $sformatf("recovery_%0d", phase_id));
        end
    endtask

    integer before_valid, before_normal;
    initial begin
        frames_file = $fopen("transactions.csv", "w");
        events_file = $fopen("events.csv", "w");
        if (!frames_file || !events_file) $fatal(1, "Cannot open evidence files");
        $fdisplay(frames_file, "id,case,status,start_ns,end_ns,gap_ns,rises,falls,command,decoded_channel,miso_payload,mosi_setup_min_ns,mosi_hold_min_ns,cs_hold_ns,dout_delay_ns");
        $fdisplay(events_file, "event,frame,time_ns,case,detail");
        $dumpfile("adc_spi.vcd");
        // Keep the VCD external: no DUT internal state is needed by the checks.
        $dumpvars(0, clk, rst_n, start, channel, miso, cs_n, sclk, mosi,
                     busy, data, valid, dout_delay_ns);
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        if (!cs_n || sclk || mosi || busy || valid || data !== 0)
            $fatal(1, "Initial reset/idle failed");
        $display("PASS CASE=reset_idle outputs=cs1_sclk0_mosi0_busy0_valid0_data000");

        channel_values[0 +: 12] = 12'h000; read_one(0, "value_000");
        channel_values[0 +: 12] = 12'h001; read_one(0, "value_001");
        channel_values[0 +: 12] = 12'hABC; read_one(0, "value_ABC");
        channel_values[0 +: 12] = 12'hFFF; read_one(0, "value_FFF");
        channel_values[0 +: 12] = 12'h555; read_one(0, "value_555");
        channel_values[0 +: 12] = 12'hAAA; read_one(0, "value_AAA");

        for (i=0; i<8; i=i+1) channel_values[12*i +: 12] = 12'h123 + 12'h111*i;
        for (i=0; i<8; i=i+1) read_one(i[2:0], $sformatf("channel_%0d", i));

        before_valid = valid_count;
        launch(3'd3, "channel_latch");
        wait (rises == 2);
        @(negedge clk); channel = 3'd6; // Change before D2/D1/D0 are sent.
        await_result(before_valid);

        before_valid = valid_count;
        launch(3'd1, "busy_shift_ignore");
        wait (rises == 8);
        @(negedge clk); channel = 7; start = 1;
        @(negedge clk); start = 0;
        await_result(before_valid);
        quiet_check(before_valid+1);
        $display("PASS CASE=busy_shift_no_queue extra_valid=0");

        before_valid = valid_count;
        launch(3'd2, "busy_gap_ignore");
        @(posedge cs_n);
        @(negedge clk); channel = 7; start = 1;
        @(negedge clk); start = 0;
        await_result(before_valid);
        quiet_check(before_valid+1);
        $display("PASS CASE=busy_gap_no_queue extra_valid=0");

        // Held start creates the earliest legal back-to-back requests.
        before_valid = valid_count;
        before_normal = normal_count;
        @(negedge clk);
        case_name = "back_to_back";
        expected_channel = 2;
        expected_data = channel_values[24 +: 12];
        channel = 2; start = 1;
        for (j=0; j<4; j=j+1) begin
            @(posedge valid);
            #2;
        end
        @(negedge clk); start = 0;
        quiet_check(before_valid+4);
        if (normal_count != before_normal+4) $fatal(1, "Back-to-back count mismatch");
        $display("PASS CASE=back_to_back frames=4 valid=4 project_gap_min_ns=2000");

        for (i=0; i<5; i=i+1)
            reset_in_phase(i, $sformatf("reset_phase_%0d", i));

        // Abort, then issue a new one-cycle request immediately after a short
        // reset. The driver must capture it and finish the reset CS-high guard.
        before_valid = valid_count;
        launch(3'd1, "fast_reset_abort");
        wait (rises == 5);
        #17; rst_n = 0;
        #2; rst_n = 1;
        // Request just 1ns before the next clk edge, then change channel
        // during WAIT_HIGH. This checks both the guard's worst clock phase
        // and command latching before CS has even gone low.
        case_name = "fast_reset_restart";
        expected_channel = 6;
        expected_data = channel_values[72 +: 12];
        channel = 6; start = 1;
        @(negedge clk); start = 0; channel = 0;
        await_result(before_valid);
        if (valid_count != before_valid+1)
            $fatal(1, "Fast reset restart accounting failed");

        dout_delay_ns = 0; read_one(7, "delay_0");
        dout_delay_ns = 199; read_one(7, "delay_199");
        dout_delay_ns = 200; read_one(7, "delay_200");
        // Additional digital margin stress, not a claimed 3.3V datasheet limit.
        dout_delay_ns = 800; read_one(7, "delay_800_stress");
        quiet_check(valid_count);
        if (normal_count != valid_count || abort_count != 5)
            $fatal(1, "Final transaction/valid accounting mismatch");
        $display("PASS ALL normal_published=%0d reset_aborted_spi=%0d reset_gap_canceled=1 end_ns=%0d",
                 valid_count, abort_count, $time);
        $fclose(frames_file); $fclose(events_file);
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1, "Global simulation timeout (5ms)");
    end
endmodule
`default_nettype wire
