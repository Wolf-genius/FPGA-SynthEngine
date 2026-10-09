`timescale 1ns/1ps
module tb_top;
    reg sys_clk = 0;
    reg rst_n = 0;
    wire i2s_bclk, i2s_lrck, i2s_din, pa_en;
    integer bits_seen = 0;
    integer frames_seen = 0;
    integer sign_changes = 0;
    reg previous_sign = 0;
    reg [15:0] right_word = 0;
    reg [15:0] left_word = 0;

    always #10 sys_clk = ~sys_clk; // 50 MHz

    top dut (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .i2s_bclk(i2s_bclk), .i2s_lrck(i2s_lrck),
        .i2s_din(i2s_din), .pa_en(pa_en)
    );

    initial begin
        #100 rst_n = 1;
    end

    always @(posedge i2s_bclk) begin
        if (rst_n) begin
            if (pa_en !== 1'b0) $fatal(1, "PA_EN should be low");
            if (bits_seen < 16) begin
                if (i2s_lrck !== 1'b0) $fatal(1, "WS should be low for right word");
                right_word = {right_word[14:0], i2s_din};
            end else begin
                if (i2s_lrck !== 1'b1) $fatal(1, "WS should be high for left word");
                left_word = {left_word[14:0], i2s_din};
            end
            bits_seen = bits_seen + 1;
            if (bits_seen == 32) begin
                if (right_word !== left_word) $fatal(1, "left/right samples differ");
                if (right_word !== 16'd3000 && right_word !== -16'sd3000)
                    $fatal(1, "unexpected sample: %0d", $signed(right_word));
                if (frames_seen != 0 && right_word[15] != previous_sign)
                    sign_changes = sign_changes + 1;
                previous_sign = right_word[15];
                frames_seen = frames_seen + 1;
                bits_seen = 0;
                right_word = 0;
                left_word = 0;
                if (frames_seen == 1000) begin
                    if (sign_changes < 17 || sign_changes > 19)
                        $fatal(1, "wrong tone rate: %0d sign changes", sign_changes);
                    $display("PASS: %0d stereo frames, matching signed samples, %0d sign changes", frames_seen, sign_changes);
                    $finish;
                end
            end
        end
    end

    initial begin
        #30000000;
        $fatal(1, "timeout");
    end
endmodule
