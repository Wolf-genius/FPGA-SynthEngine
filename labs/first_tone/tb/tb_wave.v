`timescale 1ns/1ps
// Waveform-only wrapper around the existing self-checking tb_top.
// Stops after 5 ms so the VCD is small enough to browse comfortably.
module tb_wave;
    tb_top tb();
    initial begin
        $dumpfile("D:/FPGA/first_tone_60k/tb/first_tone.vcd");
        $dumpvars(0,
            tb.rst_n,
            tb.i2s_bclk,
            tb.i2s_lrck,
            tb.i2s_din,
            tb.dut.phase,
            tb.dut.sample,
            tb.dut.bit_index
        );
        #5000000;
        $finish;
    end
endmodule
