`timescale 1ns/1ps

// Waiting tutorial controller. All inputs use clk; gate is accepted only with
// controls_valid. LOAD waits for a tagged synchronous score-memory response.
// Notes advance on a fresh correct press; H is no longer a note hold deadline.
// Successive notes need no all-zero frame. A held key cannot pass a repeat.
// Initial start and stale-input recovery still require a fresh all-zero frame.
// A rest requires release -> a further zero frame -> continuous zero hold.
module teach_ctrl #(
    parameter integer TICK_CYCLES = 50000,
    parameter integer FRAME_TIMEOUT_MS = 10
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        stop,
    input  wire        controls_valid,
    input  wire [7:0]  gate,
    output reg  [7:0]  song_addr,
    input  wire        step_ready,
    input  wire        step_valid,
    input  wire [7:0]  step_mask,
    input  wire [15:0] step_duration_ms,
    input  wire        step_last,
    output reg         active,
    output reg         done,
    output reg         fault,
    output reg  [7:0]  target_mask,
    output reg         step_pass,
    output reg         wrong_press,
    output reg         input_stale,
    output reg  [2:0]  state
);
    localparam [2:0] IDLE = 3'd0, LOAD = 3'd1, ARM = 3'd2,
                     WAIT_KEYS = 3'd3, HOLD_KEYS = 3'd4,
                     DONE = 3'd6, FAULT = 3'd7;

    function integer counter_width;
        input [63:0] count;
        reg [63:0] remaining;
        begin
            remaining = count - 64'd1;
            counter_width = 0;
            while (remaining != 64'd0) begin
                remaining = remaining >> 1;
                counter_width = counter_width + 1;
            end
            if (counter_width < 1)
                counter_width = 1;
        end
    endfunction

    // Guard elaboration widths even for invalid parameters. The public values
    // still fail immediately in simulation; the guards are not a valid setting.
    // Both multiplication operands are explicitly unsigned 64-bit quantities.
    localparam [63:0] SAFE_TICK_CYCLES =
        (TICK_CYCLES < 1) ? 64'd1 : $unsigned(TICK_CYCLES);
    localparam [63:0] SAFE_TIMEOUT_MS =
        (FRAME_TIMEOUT_MS < 1) ? 64'd1 : $unsigned(FRAME_TIMEOUT_MS);
    localparam [63:0] TIMEOUT_CYCLES = SAFE_TICK_CYCLES * SAFE_TIMEOUT_MS;
    localparam integer AGE_WIDTH = counter_width(TIMEOUT_CYCLES);
    localparam integer SUB_WIDTH = counter_width(SAFE_TICK_CYCLES);
    localparam [AGE_WIDTH-1:0] AGE_LAST = TIMEOUT_CYCLES - 64'd1;
    localparam [SUB_WIDTH-1:0] SUB_LAST = SAFE_TICK_CYCLES - 64'd1;

`ifndef SYNTHESIS
    initial begin
        if (TICK_CYCLES < 1)
            $fatal(1, "TICK_CYCLES must be >= 1");
        if (FRAME_TIMEOUT_MS < 1)
            $fatal(1, "FRAME_TIMEOUT_MS must be >= 1");
    end
`endif

    reg [AGE_WIDTH-1:0] frame_age;
    reg [SUB_WIDTH-1:0] hold_subcycle;
    reg [15:0] hold_ms;
    reg [15:0] duration_q;
    reg last_q;
    reg [7:0] gate_q;
    reg press_seen;
    reg require_release;

    wire [7:0] accepted_gate = controls_valid ? gate : gate_q;
    wire fresh_target_press = |(gate & ~gate_q & target_mask);
    // A new complete frame takes priority even at the exact timeout boundary.
    wire stale_now = !controls_valid &&
                     (input_stale || (frame_age == AGE_LAST));
    wire hold_finished = (hold_subcycle == SUB_LAST) &&
                         (hold_ms == (duration_q - 16'd1));

    // A note completes on its correct press; only rests retain timed holding.
    task complete_step;
        begin
            step_pass <= 1'b1;
            hold_subcycle <= {SUB_WIDTH{1'b0}};
            hold_ms <= 16'd0;
            press_seen <= 1'b0;
            require_release <= 1'b0;
            if (last_q) begin
                active <= 1'b0;
                done <= 1'b1;
                target_mask <= 8'd0;
                state <= DONE;
            end else if (song_addr == 8'hff) begin
                // A 256-step song without an end marker must not wrap to step 0.
                active <= 1'b0;
                fault <= 1'b1;
                target_mask <= 8'd0;
                state <= FAULT;
            end else begin
                song_addr <= song_addr + 8'd1;
                target_mask <= 8'd0;
                state <= LOAD;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            song_addr <= 8'd0;
            active <= 1'b0;
            done <= 1'b0;
            fault <= 1'b0;
            target_mask <= 8'd0;
            step_pass <= 1'b0;
            wrong_press <= 1'b0;
            input_stale <= 1'b1;
            state <= IDLE;
            frame_age <= {AGE_WIDTH{1'b0}};
            hold_subcycle <= {SUB_WIDTH{1'b0}};
            hold_ms <= 16'd0;
            duration_q <= 16'd0;
            last_q <= 1'b0;
            gate_q <= 8'd0;
            press_seen <= 1'b0;
            require_release <= 1'b1;
        end else begin
            step_pass <= 1'b0;
            wrong_press <= 1'b0;
            if (stop) begin
                // Stop wins over start, a new input frame, and step completion.
                song_addr <= 8'd0;
                active <= 1'b0;
                done <= 1'b0;
                fault <= 1'b0;
                target_mask <= 8'd0;
                input_stale <= 1'b1;
                state <= IDLE;
                frame_age <= {AGE_WIDTH{1'b0}};
                hold_subcycle <= {SUB_WIDTH{1'b0}};
                hold_ms <= 16'd0;
                duration_q <= 16'd0;
                last_q <= 1'b0;
                gate_q <= 8'd0;
                press_seen <= 1'b0;
                require_release <= 1'b1;
            end else begin
                if (controls_valid) begin
                    gate_q <= gate;
                    frame_age <= {AGE_WIDTH{1'b0}};
                    input_stale <= 1'b0;
                end else if (!input_stale) begin
                    if (frame_age == AGE_LAST)
                        input_stale <= 1'b1;
                    else
                        frame_age <= frame_age + 1'b1;
                end

                if (start) begin
                    song_addr <= 8'd0;
                    active <= 1'b1;
                    done <= 1'b0;
                    fault <= 1'b0;
                    target_mask <= 8'd0;
                    state <= LOAD;
                    press_seen <= 1'b0;
                    require_release <= 1'b1;
                    hold_subcycle <= {SUB_WIDTH{1'b0}};
                    hold_ms <= 16'd0;
                    duration_q <= 16'd0;
                    last_q <= 1'b0;
                end else begin
                    case (state)
                        IDLE, DONE, FAULT: begin end
                        LOAD: if (step_ready) begin
                            // Do not display a stale target during RAM fetch.
                            if (!step_valid || (step_duration_ms == 16'd0)) begin
                                active <= 1'b0;
                                fault <= 1'b1;
                                target_mask <= 8'd0;
                                state <= FAULT;
                            end else begin
                                target_mask <= step_mask;
                                duration_q <= step_duration_ms;
                                last_q <= step_last;
                                hold_subcycle <= {SUB_WIDTH{1'b0}};
                                hold_ms <= 16'd0;
                                press_seen <= 1'b0;
                                state <= (require_release || step_mask == 8'd0)
                                         ? ARM : WAIT_KEYS;
                            end
                        end
                        ARM: begin
                            // Even a recently cached zero cannot arm a new step.
                            // The zero frame must arrive after its LOAD edge.
                            hold_subcycle <= {SUB_WIDTH{1'b0}};
                            hold_ms <= 16'd0;
                            press_seen <= 1'b0;
                            if (!stale_now && controls_valid && (gate == 8'd0)) begin
                                require_release <= 1'b0;
                                state <= WAIT_KEYS;
                            end
                        end
                        WAIT_KEYS: begin
                            hold_subcycle <= {SUB_WIDTH{1'b0}};
                            hold_ms <= 16'd0;
                            if (stale_now) begin
                                state <= ARM;
                                press_seen <= 1'b0;
                                require_release <= 1'b1;
                            end else if (controls_valid) begin
                                if (target_mask == 8'd0) begin
                                    if (gate == 8'd0) state <= HOLD_KEYS;
                                    else wrong_press <= 1'b1;
                                end else begin
                                    // Remember a new target press while a chord
                                    // is assembled or an extra key is corrected.
                                    // A release alone cannot approve a key that
                                    // was already held when this step loaded.
                                    if ((gate & target_mask) == 8'd0)
                                        press_seen <= 1'b0;
                                    else if (fresh_target_press)
                                        press_seen <= 1'b1;
                                    if ((gate == target_mask) &&
                                        (press_seen || fresh_target_press))
                                        complete_step;
                                    else if (gate != 8'd0 && gate != target_mask)
                                        wrong_press <= 1'b1;
                                end
                            end
                        end
                        HOLD_KEYS: begin
                            // This state is used only for a rest (zero target).
                            // A wrong frame or expired input cancels its timer
                            // before considering the rest deadline.
                            if (stale_now) begin
                                hold_subcycle <= {SUB_WIDTH{1'b0}};
                                hold_ms <= 16'd0;
                                press_seen <= 1'b0;
                                require_release <= 1'b1;
                                state <= ARM;
                            end else if (accepted_gate != target_mask) begin
                                hold_subcycle <= {SUB_WIDTH{1'b0}};
                                hold_ms <= 16'd0;
                                state <= WAIT_KEYS;
                                if (controls_valid && (gate != 8'd0))
                                    wrong_press <= 1'b1;
                            end else if (hold_finished) begin
                                hold_subcycle <= {SUB_WIDTH{1'b0}};
                                hold_ms <= 16'd0;
                                complete_step;
                            end else if (hold_subcycle == SUB_LAST) begin
                                hold_subcycle <= {SUB_WIDTH{1'b0}};
                                hold_ms <= hold_ms + 16'd1;
                            end else begin
                                hold_subcycle <= hold_subcycle + 1'b1;
                            end
                        end
                        default: begin
                            active <= 1'b0;
                            fault <= 1'b1;
                            target_mask <= 8'd0;
                            state <= FAULT;
                        end
                    endcase
                end
            end
        end
    end
endmodule
