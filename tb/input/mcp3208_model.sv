`timescale 1ns/1ps
`default_nettype none

// Behavioral digital protocol model, not an analog converter model.
// Only the external SPI pins select the channel. No DUT hierarchy is used.
// Search for Start, then decode SGL and D2..D0 relative to that Start.
module mcp3208_model (
    input wire rst_n,
    input wire cs_n,
    input wire sclk,
    input wire mosi,
    input wire [95:0] channel_values,
    input integer dout_delay_ns,
    output reg miso,
    output reg [2:0] decoded_channel,
    output reg [11:0] selected_value,
    output reg [23:0] command_seen,
    output integer rise_count,
    output integer start_edge
);
    reg started;
    integer after_start;
    integer frame_id = 0;
    integer scheduled_frame;
    reg scheduled_bit;

    initial miso = 1'bx;

    always @(negedge cs_n) begin
        frame_id = frame_id + 1;
        rise_count = 0;
        start_edge = 0;
        after_start = 0;
        started = 0;
        decoded_channel = 0;
        selected_value = 12'hxxx;
        command_seen = 0;
        miso = 1'bx;
    end

    always @(posedge sclk) begin
        if (rst_n && !cs_n) begin
            rise_count = rise_count + 1;
            command_seen = {command_seen[22:0], mosi};
            if (!started) begin
                if (mosi === 1'b1) begin
                    started = 1;
                    start_edge = rise_count;
                    after_start = 0;
                end else if (mosi !== 1'b0)
                    $fatal(1, "MODEL unknown DIN before Start");
            end else begin
                after_start = after_start + 1;
                case (after_start)
                    1: if (mosi !== 1'b1)
                           $fatal(1, "MODEL expected single-ended SGL=1");
                    2: decoded_channel[2] = mosi;
                    3: decoded_channel[1] = mosi;
                    4: begin
                        decoded_channel[0] = mosi;
                        if (^decoded_channel === 1'bx)
                            $fatal(1, "MODEL unknown channel bits");
                        selected_value = channel_values[12*decoded_channel +: 12];
                    end
                endcase
            end
        end
    end

    always @(negedge sclk) begin
        if (rst_n && !cs_n) begin
            scheduled_frame = frame_id;
            if (started && after_start == 5)
                scheduled_bit = 1'b0; // Null, received on the next rising edge.
            else if (started && after_start >= 6 && after_start <= 17)
                scheduled_bit = selected_value[17-after_start];
            else
                scheduled_bit = 1'bx;
            #(dout_delay_ns);
            if (rst_n && !cs_n && frame_id == scheduled_frame)
                miso = scheduled_bit;
        end
    end

    always @(posedge cs_n or negedge rst_n)
        miso = 1'bx;
endmodule
`default_nettype wire
