// B's two-button interface. KEY1=timbre, KEY2=octave; no physical mode key.
module function_keys_input #(
    parameter integer DEBOUNCE_CYCLES = 1000000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key1_n,
    input  wire       key2_n,
    output wire [2:0] button_events,
    output wire [1:0] key_held
);
    key_press_event #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key1 (
        .clk(clk), .rst_n(rst_n), .key_n(key1_n),
        .key_down(key_held[0]), .press_event(button_events[0])
    );
    key_press_event #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key2 (
        .clk(clk), .rst_n(rst_n), .key_n(key2_n),
        .key_down(key_held[1]), .press_event(button_events[1])
    );
    assign button_events[2] = 1'b0;
endmodule
