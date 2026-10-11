`timescale 1ns/1ps

module tb_adc_ch0;

    reg clk = 0;
    always #10 clk = ~clk; // 20ns周期，即50MHz

    reg rst_n = 0;
    reg start = 0;
    reg miso = 1'bx;

    wire cs_n;
    wire sclk;
    wire mosi;
    wire busy;
    wire [11:0] data;
    wire valid;

    adc_ch0 dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .miso(miso),
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .busy(busy),
        .data(data),
        .valid(valid)
    );

    reg [11:0] model_value = 0;
    reg [11:0] latched_value = 0;
    reg [23:0] tx_seen = 0;

    integer rising_count = 0;
    integer valid_count = 0;
    integer before_count;

    reg previous_valid = 0;
    time last_edge = 0;

    // 模拟ADC：片选开始时锁定本次要返回的数。
    always @(negedge cs_n) begin
        rising_count = 0;
        tx_seen = 0;
        latched_value = model_value;
        miso = 1'bx;
        last_edge = 0;
    end

    // 记录主机发送的命令和时钟数量。
    always @(posedge sclk) begin
        if (rst_n && !cs_n) begin
            rising_count = rising_count + 1;
            tx_seen = {tx_seen[22:0], mosi};
        end
    end

    // 模拟ADC在下降沿后更新DOUT。
    // 加200ns延迟，避免使用零延迟的理想模型。
    always @(negedge sclk) begin
        if (rst_n && !cs_n) begin
            if (rising_count == 11)
                miso <= #200 1'b0; // Null位
            else if (rising_count >= 12 &&
                     rising_count <= 23)
                miso <= #200 latched_value[23-rising_count];
            else
                miso <= #200 1'bx;
        end
    end

    // 检查SPI半周期应为1000ns。
    always @(sclk) begin
        if (rst_n && !cs_n) begin
            if (last_edge != 0 &&
                ($time - last_edge) != 1000)
                $fatal(1, "SPI half-period is not 1000ns");

            last_edge = $time;
        end
    end

    // 一次正常事务结束时检查完整命令与时钟数。
    always @(posedge cs_n) begin
        if (rst_n) begin
            if (rising_count != 24)
                $fatal(1, "Expected 24 clocks, got %0d",
                       rising_count);

            if (tx_seen !== 24'h060000)
                $fatal(1, "Wrong CH0 command: %h", tx_seen);

            if (sclk !== 1'b0)
                $fatal(1, "SCLK must end low");
        end
    end

    // 检查valid只持续一个主时钟周期。
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            previous_valid = 0;
        end else begin
            if (valid && previous_valid)
                $fatal(1, "valid lasted more than one cycle");

            if (valid) begin
                valid_count = valid_count + 1;

                if (busy !== 1'b0 ||
                    cs_n !== 1'b1 ||
                    sclk !== 1'b0)
                    $fatal(1, "Bad outputs when valid=1");
            end

            previous_valid = valid;
        end
    end

    task check_value;
        input [11:0] expected;
        integer count_before;
        begin
            @(negedge clk);
            count_before = valid_count;
            model_value = expected;
            start = 1;

            @(negedge clk);
            start = 0;

            wait (valid === 1'b1);
            #2;

            if (data !== expected)
                $fatal(1, "Expected %h, got %h",
                       expected, data);

            if (valid_count != count_before + 1)
                $fatal(1, "Wrong valid count");

            $display("PASS value=%h", expected);

            repeat (3) @(negedge clk);

            if (data !== expected)
                $fatal(1, "data did not hold its value");
        end
    endtask

    initial begin
        $dumpfile("sim/adc_ch0.vcd");
        $dumpvars(0, tb_adc_ch0);

        repeat (5) @(negedge clk);
        rst_n = 1;

        check_value(12'h000);
        check_value(12'h001);
        check_value(12'h555);
        check_value(12'hAAA);
        check_value(12'hFFF);

        // 测试通信途中复位：本次读取应被取消。
        @(negedge clk);
        before_count = valid_count;
        model_value = 12'h123;
        start = 1;

        @(negedge clk);
        start = 0;

        wait (rising_count == 10);
        @(negedge clk);
        rst_n = 0;

        #1;
        if (cs_n !== 1'b1 || sclk !== 1'b0 ||
            busy !== 1'b0 || valid !== 1'b0 ||
            data !== 12'h000)
            $fatal(1, "Reset did not restore idle outputs");

        repeat (5) @(negedge clk);
        rst_n = 1;

        repeat (3000) @(negedge clk);
        if (valid_count != before_count)
            $fatal(1, "Aborted transfer produced valid");

        $display("PASS reset-abort");

        // 复位后应可以重新读取。
        check_value(12'hA55);

        // 测试busy期间的新请求应被忽略。
        @(negedge clk);
        before_count = valid_count;
        model_value = 12'h321;
        start = 1;

        @(negedge clk);
        start = 0;

        wait (rising_count == 8);
        @(negedge clk);
        model_value = 12'hFED;
        start = 1;

        @(negedge clk);
        start = 0;

        wait (valid === 1'b1);
        #2;

        if (data !== 12'h321)
            $fatal(1, "Busy request changed current transfer");

        repeat (3000) @(negedge clk);
        if (valid_count != before_count + 1)
            $fatal(1, "Busy request was unexpectedly queued");

        $display("PASS busy-ignore");
        $display("PASS: all CH0 tests completed");
        $finish;
    end

    // 防止程序因一直等不到valid而无限运行。
    initial begin
        #2000000;
        $fatal(1, "Simulation timeout");
    end
endmodule