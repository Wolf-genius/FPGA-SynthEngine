`timescale 1ns/1ps

// 仿真顶层：tb_DDS。只用于仿真，不加入综合源文件。
// 50MHz 主时钟，每 1024 个周期采样一次：Fs = 48,828.125Hz。
// 440Hz 的正确相位步长为 round(440 * 2^32 / Fs) = 38702809。
module tb_DDS;
    reg sys_clk;
    reg rst_n;
    reg sample_ce;
    wire [31:0] phase;
    wire signed [15:0] sample;

    localparam [31:0] EXPECTED_STEP = 32'd38702809;
    localparam signed [15:0] LEVEL = 16'sd8000;
    reg [31:0] expected_phase;
    reg signed [15:0] expected_sample;
    reg [31:0] previous_phase;
    reg signed [15:0] previous_sample;
    integer errors;
    integer checks;
    integer enabled_samples;
    integer wraps;
    integer rising_edges;
    realtime first_rise;
    realtime last_rise;
    real measured_hz;

    DDS dut (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .sample_ce(sample_ce),
        .phase(phase),
        .sample(sample)
    );

    // 20ns 一个周期，即 50MHz。
    initial sys_clk = 1'b0;
    always #10 sys_clk = ~sys_clk;

    // 参考模型：sample 使用更新前的相位，与当前 DDS 的接口行为一致。
    // 延后 1ns 检查，等待非阻塞赋值完成。
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_phase = 32'd0;
            expected_sample = 16'sd0;
        end else if (sample_ce) begin
            expected_sample = expected_phase[31] ? LEVEL : -LEVEL;
            expected_phase = expected_phase + EXPECTED_STEP;
        end

        #1;
        checks = checks + 1;
        if ((phase !== expected_phase) || (sample !== expected_sample)) begin
            errors = errors + 1;
            // 限制打印次数，避免频率字错误时刷屏。
            if (errors <= 10)
                $display("ERROR t=%0t ce=%b phase=%h expected=%h sample=%0d expected=%0d",
                         $time, sample_ce, phase, expected_phase,
                         sample, expected_sample);
        end

        if (rst_n && sample_ce) begin
            enabled_samples = enabled_samples + 1;
            if (phase < previous_phase)
                wraps = wraps + 1;
            // 负振幅到正振幅的跳变，每个完整周期出现一次。
            if ((previous_sample < 0) && (sample > 0)) begin
                if (rising_edges == 0)
                    first_rise = $realtime;
                last_rise = $realtime;
                rising_edges = rising_edges + 1;
            end
        end

        if (!rst_n) begin
            previous_phase = 32'd0;
            previous_sample = 16'sd0;
        end else begin
            previous_phase = phase;
            previous_sample = sample;
        end
    end

    // 在下降沿改变输入，避免与 DUT 上升沿采样竞争。
    // 连续调用时，相邻请求正好相隔 1024 个主时钟周期。
    task request_sample;
        begin
            @(negedge sys_clk);
            sample_ce = 1'b1;
            @(negedge sys_clk);
            sample_ce = 1'b0;
            repeat (1023) @(posedge sys_clk);
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        enabled_samples = 0;
        wraps = 0;
        rising_edges = 0;
        first_rise = 0.0;
        last_rise = 0.0;
        expected_phase = 0;
        expected_sample = 0;
        previous_phase = 0;
        previous_sample = 0;
        sample_ce = 1'b0;
        rst_n = 1'b1;

        $dumpfile("tb_DDS.vcd");
        $dumpvars(0, tb_DDS);

        // 1. 在非时钟沿拉低复位，验证异步清零。
        #3 rst_n = 1'b0;
        #40;
        @(negedge sys_clk);
        rst_n = 1'b1;

        // 2. 没有采样请求时，phase 和 sample 必须保持。
        repeat (12) @(negedge sys_clk);

        // 3. 按真实采样间隔运行，验证累加、回绕、方波和频率。
        repeat (2048) request_sample;
        #2;
        if ((wraps == 0) || (rising_edges < 2)) begin
            errors = errors + 1;
            $display("ERROR: insufficient wraps or waveform edges");
        end else begin
            measured_hz = (rising_edges - 1) * 1.0e9 / (last_rise - first_rise);
            $display("Measured frequency = %0.3f Hz (target 440Hz)", measured_hz);
            // 有限采样窗口存在边沿量化，留出 1Hz 测量容差。
            if ((measured_hz < 439.0) || (measured_hz > 441.0)) begin
                errors = errors + 1;
                $display("ERROR: frequency outside 439..441Hz");
            end
        end

        // 4. 运行后暂停，验证非零相位也能够保持。
        repeat (20) @(negedge sys_clk);

        // 5. 连续使能四周期，每周期都应只推进一步。
        @(negedge sys_clk);
        sample_ce = 1'b1;
        repeat (4) @(negedge sys_clk);
        sample_ce = 1'b0;

        // 6. 运行中再次异步复位，然后重新启动。
        #3 rst_n = 1'b0;
        #40;
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (4) request_sample;
        @(negedge sys_clk);

        $display("Checks=%0d enabled_samples=%0d wraps=%0d errors=%0d",
                 checks, enabled_samples, wraps, errors);
        if (errors == 0) begin
            $display("PASS: DDS reset, enable, phase, wrap and square-wave checks passed.");
            $finish;
        end else begin
            $fatal(1, "FAIL: DDS has %0d errors", errors);
        end
    end

    // 防止意外卡住，100ms 后终止。
    initial begin
        #100000000;
        $fatal(1, "FAIL: simulation timeout");
    end
endmodule
