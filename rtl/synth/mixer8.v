`timescale 1ns/1ps
`default_nettype none
// Eight signed 16-bit inputs, extended BEFORE addition; fixed /8.
module mixer8 (
    input wire [127:0] samples,
    output wire signed [18:0] sum19,
    output wire signed [15:0] mixed_sample
);
    wire signed [18:0] s [0:7];
    genvar i;
    generate for(i=0;i<8;i=i+1) begin : extend_samples
        assign s[i] = {{3{samples[i*16+15]}}, samples[i*16 +: 16]};
    end endgenerate
    // Balanced tree bounds each partial sum within signed 19 bits.
    wire signed [18:0] p0=s[0]+s[1], p1=s[2]+s[3];
    wire signed [18:0] p2=s[4]+s[5], p3=s[6]+s[7];
    wire signed [18:0] q0=p0+p1, q1=p2+p3;
    wire signed [18:0] scaled;
    assign sum19=q0+q1;
    assign scaled=sum19 >>> 3;
    assign mixed_sample=scaled[15:0];
endmodule
`default_nettype wire
