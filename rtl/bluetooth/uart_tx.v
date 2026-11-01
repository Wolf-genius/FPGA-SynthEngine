`timescale 1ns/1ps
`default_nettype none
module uart_tx #(parameter integer CLKS_PER_BIT = 5208)(
    input wire clk, rst_n,
    input wire start,
    input wire [7:0] data,
    output reg tx, busy
);
    reg [9:0] frame;
    reg [3:0] bit_index;
    reg [31:0] timer;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1; busy <= 0; timer <= 0; bit_index <= 0; frame <= 10'h3ff;
        end else if (!busy) begin
            tx <= 1;
            if (start) begin
                frame <= {1'b1, data, 1'b0};
                bit_index <= 0; timer <= 0; tx <= 0; busy <= 1;
            end
        end else if (timer == CLKS_PER_BIT-1) begin
            timer <= 0;
            if (bit_index == 9) begin tx <= 1; busy <= 0; end
            else begin
                bit_index <= bit_index+1'b1;
                tx <= frame[bit_index+1'b1];
            end
        end else timer <= timer+1'b1;
    end
endmodule
`default_nettype wire
