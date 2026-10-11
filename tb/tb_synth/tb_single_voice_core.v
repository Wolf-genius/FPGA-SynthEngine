`timescale 1ns/1ps

module tb_single_voice_core;

    reg clk = 1'b0;
    always #10 clk = ~clk;  // 50MHz

    reg rst_n = 1'b0;
    reg sample_ce = 1'b0;

    // 仿真专用：每次前进四分之一周期
    reg [31:0] phase_step = 32'h4000_0000;

    reg [7:0] gate = 8'd0;
    reg [127:0] key_gain = 128'd0;
    reg controls_valid = 1'b0;

    wire signed [15:0] mixed_sample;
    wire mixed_valid;

    integer errors = 0;

    single_voice_core dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .sample_ce      (sample_ce),
        .phase_step     (phase_step),
        .gate           (gate),
        .key_gain       (key_gain),
        .controls_valid (controls_valid),
        .mixed_sample   (mixed_sample),
        .mixed_valid    (mixed_valid)
    );

    // --------------------------------------------------
    // 复位
    // --------------------------------------------------

    task reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            sample_ce = 1'b0;
            controls_valid = 1'b0;
            gate = 8'd0;
            key_gain = 128'd0;

            repeat (3) @(posedge clk);

            @(negedge clk);
            rst_n = 1'b1;

            #1;
            if (mixed_sample !== 16'sd0 ||
                mixed_valid !== 1'b0) begin
                $display("FAIL: reset output");
                errors = errors + 1;
            end
        end
    endtask

    // --------------------------------------------------
    // 提交通道0控制帧
    // --------------------------------------------------

    task send_control;
        input pressed;
        input [15:0] gain_value;

        begin
            @(negedge clk);

            gate = 8'd0;
            gate[0] = pressed;

            key_gain = 128'd0;
            key_gain[15:0] = gain_value;

            controls_valid = 1'b1;

            @(negedge clk);
            controls_valid = 1'b0;
        end
    endtask

    // --------------------------------------------------
    // 请求一个采样并检查结果
    // --------------------------------------------------

    task request_and_check;
        input signed [15:0] expected;

        begin
            @(negedge clk);
            sample_ce = 1'b1;

            // 第一个上升沿：读表并锁定控制
            @(negedge clk);
            sample_ce = 1'b0;

            // 第二个上升沿：登记输出
            @(posedge clk);
            #1;

            if (mixed_valid !== 1'b1 ||
                mixed_sample !== expected) begin

                $display(
                    "FAIL: expected=%0d actual=%0d valid=%b",
                    expected,
                    mixed_sample,
                    mixed_valid
                );

                errors = errors + 1;
            end else begin
                $display("PASS: sample=%0d", mixed_sample);
            end

            // 没有后续请求，valid应恢复为0
            @(posedge clk);
            #1;

            if (mixed_valid !== 1'b0) begin
                $display("FAIL: mixed_valid did not clear");
                errors = errors + 1;
            end
        end
    endtask

    // --------------------------------------------------
    // 正式测试
    // --------------------------------------------------

    initial begin
        $dumpfile("tb/synth/tb_single_voice_core.vcd");
        $dumpvars(0, tb_single_voice_core);

        // 1. 复位后没有控制帧，必须静音
        reset_dut;

        request_and_check(16'sd0);
        request_and_check(16'sd0);

        // 2. gate=1，但gain=0：仍然静音
        reset_dut;
        send_control(1'b1, 16'd0);

        request_and_check(16'sd0);
        request_and_check(16'sd0);
        request_and_check(16'sd0);
        request_and_check(16'sd0);

        // 3. 半增益
        reset_dut;
        send_control(1'b1, 16'd32768);

        request_and_check(16'sd0);
        request_and_check(16'sd4000);
        request_and_check(16'sd0);
        request_and_check(-16'sd4000);

        // 4. 接近满增益
        reset_dut;
        send_control(1'b1, 16'd65535);

        request_and_check(16'sd0);
        request_and_check(16'sd7999);
        request_and_check(16'sd0);
        request_and_check(-16'sd8000);

        // 5. gate=0，即使gain最大也必须静音
        reset_dut;
        send_control(1'b0, 16'd65535);

        request_and_check(16'sd0);
        request_and_check(16'sd0);
        request_and_check(16'sd0);
        request_and_check(16'sd0);

        // 6. 不复位，演奏中改变力度
        reset_dut;
        send_control(1'b1, 16'd32768);

        request_and_check(16'sd0);
        request_and_check(16'sd4000);

        send_control(1'b1, 16'd65535);

        request_and_check(16'sd0);
        request_and_check(-16'sd8000);

        // 7. 演奏中松开
        send_control(1'b0, 16'd0);

        request_and_check(16'sd0);
        request_and_check(16'sd0);

        // 8. 控制更新与采样请求同沿
        // 本次用旧半增益，下次才使用新满增益
        reset_dut;
        send_control(1'b1, 16'd32768);

        // 地址0，随后相位到四分之一周期
        request_and_check(16'sd0);

        @(negedge clk);
        gate = 8'b0000_0001;
        key_gain = 128'd0;
        key_gain[15:0] = 16'd65535;
        controls_valid = 1'b1;
        sample_ce = 1'b1;

        @(negedge clk);
        controls_valid = 1'b0;
        sample_ce = 1'b0;

        @(posedge clk);
        #1;

        // 同沿仍使用旧半增益：8000 × 0.5 = 4000
        if (mixed_valid !== 1'b1 ||
            mixed_sample !== 16'sd4000) begin
            $display("FAIL: simultaneous update");
            errors = errors + 1;
        end else begin
            $display("PASS: simultaneous update uses old control");
        end

        // 后续采样使用新满增益
        request_and_check(16'sd0);
        request_and_check(-16'sd8000);

        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $fatal(1, "TEST FAILED: %0d errors", errors);
        end
    end

endmodule