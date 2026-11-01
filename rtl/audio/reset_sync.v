module reset_sync (
    input  wire clk,
    input  wire rst_n,
    output wire run_rst_n
);
    reg [1:0] release_ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            release_ff <= 2'b00;
        else
            release_ff <= {release_ff[0], 1'b1};
    end
    assign run_rst_n = release_ff[1];
endmodule
