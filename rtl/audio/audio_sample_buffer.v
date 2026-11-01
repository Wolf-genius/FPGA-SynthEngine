module audio_sample_buffer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [15:0] mixed_data,
    input  wire        mixed_valid,
    output reg         sample_ce,
    output wire [15:0] sample_data,
    output reg  [31:0] underrun_count,
    output reg  [31:0] discarded_count
);
    reg [15:0] pending_data;
    reg        ready;
    reg        waiting;
    reg        expired;
    reg        started;

    // audio_tx reads this OLD buffered value on the frame_start clock edge.
    // A response arriving on that same edge is too late for this frame.
    assign sample_data = ready ? pending_data : 16'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_data    <= 16'd0;
            ready           <= 1'b0;
            waiting         <= 1'b0;
            expired         <= 1'b0;
            started         <= 1'b0;
            sample_ce       <= 1'b0;
            underrun_count  <= 32'd0;
            discarded_count <= 32'd0;
        end else begin
            sample_ce <= 1'b0;
            if (frame_start) begin
                if (started && !ready && (underrun_count != 32'hffffffff))
                    underrun_count <= underrun_count + 32'd1;
                started <= 1'b1;
                ready   <= 1'b0;
                if (!waiting) begin
                    waiting   <= 1'b1;
                    expired   <= 1'b0;
                    sample_ce <= 1'b1;
                end else begin
                    // Do not overlap requests without response IDs.
                    // Drain the old response first, then resume at a frame.
                    expired <= 1'b1;
                end
            end
            if (mixed_valid) begin
                if (waiting) begin
                    waiting <= 1'b0;
                    if (expired || frame_start) begin
                        if (discarded_count != 32'hffffffff)
                            discarded_count <= discarded_count + 32'd1;
                    end else begin
                        pending_data <= mixed_data;
                        ready        <= 1'b1;
                    end
                end else begin
                    if (discarded_count != 32'hffffffff)
                        discarded_count <= discarded_count + 32'd1;
                end
            end
        end
    end
endmodule
