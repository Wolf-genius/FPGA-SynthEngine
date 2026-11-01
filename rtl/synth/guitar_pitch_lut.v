`timescale 1ns/1ps
`default_nettype none
module guitar_pitch_lut(input wire [31:0] phase_step,
    output reg supported,output reg [9:0] delay_integer,output reg [15:0] fraction);
    always @* begin
        supported=0;delay_integer=10'd2;fraction=0;
        case(phase_step)
            32'd11506414: begin supported=1'b1;delay_integer=10'd372;fraction=16'd50281;end
            32'd12915513: begin supported=1'b1;delay_integer=10'd332;fraction=16'd2838;end
            32'd14497173: begin supported=1'b1;delay_integer=10'd295;fraction=16'd49965;end
            32'd15359220: begin supported=1'b1;delay_integer=10'd279;fraction=16'd8812;end
            32'd17240141: begin supported=1'b1;delay_integer=10'd248;fraction=16'd41025;end
            32'd19351404: begin supported=1'b1;delay_integer=10'd221;fraction=16'd29231;end
            32'd21721217: begin supported=1'b1;delay_integer=10'd197;fraction=16'd15167;end
            32'd23012828: begin supported=1'b1;delay_integer=10'd186;fraction=16'd8757;end
            32'd25831026: begin supported=1'b1;delay_integer=10'd165;fraction=16'd50571;end
            32'd28994347: begin supported=1'b1;delay_integer=10'd147;fraction=16'd41366;end
            32'd30718440: begin supported=1'b1;delay_integer=10'd139;fraction=16'd20790;end
            32'd34480283: begin supported=1'b1;delay_integer=10'd124;fraction=16'd4128;end
            32'd38702809: begin supported=1'b1;delay_integer=10'd110;fraction=16'd30999;end
            32'd43442435: begin supported=1'b1;delay_integer=10'd98;fraction=16'd23967;end
            32'd46025656: begin supported=1'b1;delay_integer=10'd92;fraction=16'd53530;end
            32'd51662052: begin supported=1'b1;delay_integer=10'd82;fraction=16'd41669;end
            32'd57988694: begin supported=1'b1;delay_integer=10'd73;fraction=16'd37067;end
            32'd61436880: begin supported=1'b1;delay_integer=10'd69;fraction=16'd26779;end
            32'd68960566: begin supported=1'b1;delay_integer=10'd61;fraction=16'd51216;end
            32'd77405618: begin supported=1'b1;delay_integer=10'd54;fraction=16'd64652;end
            32'd86884870: begin supported=1'b1;delay_integer=10'd48;fraction=16'd61136;end
            32'd92051312: begin supported=1'b1;delay_integer=10'd46;fraction=16'd10381;end
            default:begin end
        endcase
    end
endmodule
`default_nettype wire
