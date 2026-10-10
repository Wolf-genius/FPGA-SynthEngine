module led_blink (
    input  wire clk,
    input  wire rst_n,
    output reg  led
);

    reg [24:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 25'd0;
            led     <= 1'b0;
        end
        else if (counter == 25'd24_999_999) begin
            counter <= 25'd0;
            led     <= ~led;
        end
        else begin
            counter <= counter + 25'd1;
        end
    end

endmodule