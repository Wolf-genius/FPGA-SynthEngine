`timescale 1ns/1ps

module audio_tx_tb;

    reg  clk;
    reg  rst_n;
    wire bclk;
    wire ws;
    wire din;
    wire sample_ce;

    time last_edge;

    audio_tx dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .sample_data (16'h1234),
    .bclk        (bclk),
    .ws          (ws),
    .din         (din),
    .sample_ce   (sample_ce)
);

    always #10 clk = ~clk;

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;

        $dumpfile("audio_tx_tb.vcd");
        $dumpvars(0, audio_tx_tb);

        #45;

        if (bclk !== 1'b0 || ws !== 1'b0) begin
            $display("FAIL: reset outputs should be 0");
            $finish;
        end

        rst_n = 1'b1;

        // 检查BCLK半周期
        @(posedge bclk);
        last_edge = $time;

        repeat (20) begin
            @(bclk);

            if (($time - last_edge) != 160) begin
                $display("FAIL: BCLK half period = %0d ns",
                         $time - last_edge);
                $finish;
            end

            last_edge = $time;
        end

        // 从第一次WS上升沿开始测量
        @(posedge ws);
        last_edge = $time;

        // 检查连续4个声道时隙
        repeat (4) begin
            @(ws);

            if (($time - last_edge) != 10240) begin
                $display("FAIL: WS half period = %0d ns",
                         $time - last_edge);
                $finish;
            end

            // WS切换时，BCLK应刚变为低电平
            if (bclk !== 1'b0) begin
                $display("FAIL: WS changed outside BCLK falling edge");
                $finish;
            end

            last_edge = $time;
        end

        $display("PASS: BCLK=320 ns, WS half=10240 ns, frame=20480 ns");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule