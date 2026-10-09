module DDS(
    input wire sys_clk,
    input wire rst_n,
    input wire sample_ce,
    output reg [31:0] phase,
    output reg signed [15:0] sample
);

    localparam [31:0] STEP_440 = 32'd38702809;
    localparam [31:0] STEP_880 = 32'd77405619;

    localparam signed [15:0] level = 16'sd8000 ;


    wire signed [15:0] next_sample;
    assign next_sample = phase[31] ? level : -level;
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) begin
            phase <= 32'd0;
            sample <= 16'd0;
        end
        else if (sample_ce) begin
            phase <= phase + STEP_440; //440Hz
            sample <= next_sample;
        end
    end



endmodule