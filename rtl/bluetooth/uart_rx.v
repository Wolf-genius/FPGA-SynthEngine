`timescale 1ns/1ps
`default_nettype none
// 8 data bits, no parity, 1 stop bit. Idle level is high.
module uart_rx #(parameter integer CLKS_PER_BIT = 5208)(
    input wire clk, rst_n, rx,
    output reg [7:0] data,
    output reg valid, framing_error
);
    reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
        else begin rx_meta <= rx; rx_sync <= rx_meta; end

    localparam IDLE=0, START=1, DATA=2, STOP=3, WAIT_HIGH=4;
    reg [2:0] state;
    reg [31:0] timer;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; timer <= 0; bit_index <= 0;
            shift <= 0; data <= 0; valid <= 0; framing_error <= 0;
        end else begin
            valid <= 0;
            framing_error <= 0;
            case (state)
                IDLE: begin
                    timer <= 0;
                    if (!rx_sync) state <= START;
                end
                START: begin
                    if (timer == CLKS_PER_BIT/2-1) begin
                        timer <= 0;
                        if (!rx_sync) begin state <= DATA; bit_index <= 0; end
                        else state <= IDLE; // Reject a short low glitch.
                    end else timer <= timer+1'b1;
                end
                DATA: begin
                    if (timer == CLKS_PER_BIT-1) begin
                        timer <= 0;
                        shift[bit_index] <= rx_sync; // UART sends LSB first.
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index+1'b1;
                    end else timer <= timer+1'b1;
                end
                STOP: begin
                    if (timer == CLKS_PER_BIT-1) begin
                        timer <= 0;
                        if (rx_sync) begin data <= shift; valid <= 1; state <= IDLE; end
                        else begin framing_error <= 1; state <= WAIT_HIGH; end
                    end else timer <= timer+1'b1;
                end
                WAIT_HIGH: if (rx_sync) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
