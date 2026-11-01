// Active-low mechanical button, all logic in the clk domain.
// Requires a qualified release after reset before the first press can fire.
module key_press_event #(
    parameter integer DEBOUNCE_CYCLES = 1000000 // 20 ms at 50 MHz
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  key_down,
    output reg  press_event
);
    localparam integer COUNT_WIDTH = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam [COUNT_WIDTH-1:0] LAST_COUNT = DEBOUNCE_CYCLES - 1;
    localparam [COUNT_WIDTH-1:0] ONE = 1;
    reg key_meta, key_sync;
    reg [1:0] sync_ready;
    reg previous_n;
    reg [COUNT_WIDTH-1:0] stable_count;
    reg armed;

    // Neither the metastability catcher nor raw key_n feeds the debounce logic.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1;
            key_sync <= 1'b1;
            sync_ready <= 2'b00;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;
            sync_ready <= {sync_ready[0], 1'b1};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_n <= 1'b1;
            stable_count <= {COUNT_WIDTH{1'b0}};
            armed <= 1'b0;
            key_down <= 1'b0;
            press_event <= 1'b0;
        end else begin
            press_event <= 1'b0;
            // Wait until both synchronizer stages contain post-reset samples.
            if (sync_ready[1]) begin
                previous_n <= key_sync;
                if (key_sync != previous_n)
                    stable_count <= (DEBOUNCE_CYCLES == 1) ? {COUNT_WIDTH{1'b0}} : ONE;
                else if (stable_count < LAST_COUNT)
                    stable_count <= stable_count + ONE;

                // The changed sample is the first sample of the new run.
                // On an unchanged input, old count N-1 means this is sample N.
                if ((DEBOUNCE_CYCLES == 1) ||
                    ((key_sync == previous_n) && (stable_count == LAST_COUNT))) begin
                    key_down <= !key_sync;
                    if (key_sync) begin
                        armed <= 1'b1;
                    end else begin
                        if (armed)
                            press_event <= 1'b1;
                        armed <= 1'b0;
                    end
                end
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (DEBOUNCE_CYCLES < 1)
            $fatal(1, "DEBOUNCE_CYCLES must be >= 1");
    end
    // synthesis translate_on
endmodule
