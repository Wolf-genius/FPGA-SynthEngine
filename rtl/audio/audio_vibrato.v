`timescale 1ns/1ps
`default_nettype none
// Shared pitch vibrato, not amplitude tremolo. A sinusoidally modulated
// fractional delay follows the complete piano/guitar mix. No RAM reset.
// One result per accepted sample, exactly seven clk cycles later. Samples
// must be >=8 clocks apart (the board interval is 1024 clocks).
module audio_vibrato #(
    parameter integer BUFFER_BITS=7,
    parameter integer BASE_DELAY_SAMPLES=64,
    parameter integer DEPTH_SAMPLES=16,
    parameter [31:0] LFO_PHASE_STEP=32'd439805,
    parameter integer RAMP_BITS=8,
    parameter LFO_FILE="tables/vibrato_sine256.hex"
)(
    input wire clk,rst_n,enable,in_valid,
    input wire signed [15:0] in_sample,
    output reg signed [15:0] out_sample,
    output reg out_valid,
    output reg overrun
);
    localparam integer BUFFER_SIZE=1<<BUFFER_BITS;
    localparam integer READY_SAMPLES=BASE_DELAY_SAMPLES+DEPTH_SAMPLES+2;
    localparam integer BLEND_WIDTH=19+RAMP_BITS;
    localparam [RAMP_BITS:0] FULL_WET=(1<<RAMP_BITS);
    localparam [2:0] IDLE=0,LFO_MULT=1,SET_DELAY=2,READ_FIRST=3,
                     READ_SECOND=4,INTERPOLATE=5,BLEND=6,PUBLISH=7;
    reg [2:0] state;
    reg signed [15:0] history[0:BUFFER_SIZE-1];
    reg signed [15:0] lfo_rom[0:255];
    initial $readmemh(LFO_FILE,lfo_rom);

    reg [BUFFER_BITS-1:0] write_ptr,write_index,read_addr0,read_addr1;
    reg [BUFFER_BITS:0] filled;
    reg [31:0] lfo_phase;
    reg [15:0] lfo_fraction,delay_fraction;
    reg signed [15:0] lfo_a,lfo_b,lfo_base,ram_read,tap0,dry_q;
    reg signed [33:0] lfo_product,interpolation_product;
    reg signed [BLEND_WIDTH-1:0] blend_product;
    reg [RAMP_BITS:0] wet_amount,mix_level;
    reg ready_q;

    wire accept=rst_n && in_valid && state==IDLE;
    wire history_ready=(filled>=READY_SAMPLES);
    wire wet_requested=enable && history_ready;
    wire [RAMP_BITS:0] next_wet=wet_requested ?
        (wet_amount==FULL_WET ? FULL_WET : wet_amount+1'b1) :
        (wet_amount==0 ? {RAMP_BITS+1{1'b0}} : wet_amount-1'b1);
    wire [7:0] lfo_index=lfo_phase[31:24];
    wire [7:0] lfo_next_index=lfo_index+1'b1;
    wire [BUFFER_BITS-1:0] ram_addr=(state==READ_SECOND)?read_addr1:read_addr0;

    // Registered, single-write/single-read history. Read addresses never touch
    // the current write and are used only after all required samples exist.
    always @(posedge clk) begin
        if(accept) begin
            history[write_ptr]<=in_sample;
            lfo_a<=lfo_rom[lfo_index];
            lfo_b<=lfo_rom[lfo_next_index];
        end
        if(ready_q && (state==READ_FIRST || state==READ_SECOND))
            ram_read<=history[ram_addr];
    end

    wire signed [16:0] lfo_difference=$signed({lfo_b[15],lfo_b})-
                                      $signed({lfo_a[15],lfo_a});
    wire signed [16:0] lfo_value=$signed({lfo_base[15],lfo_base})+
                                $signed(lfo_product[32:16]);
    // lfo_value is Q15; multiplying by 2*depth gives a Q16 sample delay.
    wire signed [31:0] delay_offset=lfo_value*(2*DEPTH_SAMPLES);
    wire signed [31:0] delay_q16=(BASE_DELAY_SAMPLES*65536)+delay_offset;
    wire [BUFFER_BITS-1:0] delay_integer=delay_q16[16+:BUFFER_BITS];
    wire signed [16:0] audio_difference=$signed({ram_read[15],ram_read})-
                                        $signed({tap0[15],tap0});
    wire signed [16:0] wet_value=$signed({tap0[15],tap0})+
                                $signed(interpolation_product[32:16]);
    wire signed [16:0] wet_dry_difference=wet_value-$signed({dry_q[15],dry_q});
    wire signed [16:0] blended_value=$signed({dry_q[15],dry_q})+
                                    $signed(blend_product[16+RAMP_BITS:RAMP_BITS]);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;write_ptr<=0;write_index<=0;filled<=0;
            read_addr0<=0;read_addr1<=0;lfo_phase<=0;lfo_fraction<=0;
            delay_fraction<=0;lfo_base<=0;lfo_product<=0;
            interpolation_product<=0;blend_product<=0;tap0<=0;dry_q<=0;
            wet_amount<=0;mix_level<=0;ready_q<=0;
            out_sample<=0;out_valid<=0;overrun<=0;
        end else begin
            out_valid<=0;
            if(in_valid && state!=IDLE)overrun<=1;
            case(state)
                IDLE:if(in_valid)begin
                    dry_q<=in_sample;write_index<=write_ptr;write_ptr<=write_ptr+1'b1;
                    if(filled<BUFFER_SIZE)filled<=filled+1'b1;
                    ready_q<=history_ready;
                    wet_amount<=next_wet;mix_level<=next_wet;
                    lfo_fraction<=lfo_phase[23:8];lfo_phase<=lfo_phase+LFO_PHASE_STEP;
                    state<=LFO_MULT;
                end
                LFO_MULT:begin
                    lfo_base<=lfo_a;
                    lfo_product<=lfo_difference*$signed({1'b0,lfo_fraction});
                    state<=SET_DELAY;
                end
                SET_DELAY:begin
                    read_addr0<=write_index-delay_integer;
                    read_addr1<=write_index-delay_integer-1'b1;
                    delay_fraction<=delay_q16[15:0];state<=READ_FIRST;
                end
                READ_FIRST:state<=READ_SECOND;
                READ_SECOND:begin
                    tap0<=ready_q?ram_read:16'sd0;state<=INTERPOLATE;
                end
                INTERPOLATE:begin
                    interpolation_product<=ready_q ?
                        audio_difference*$signed({1'b0,delay_fraction}) : 34'sd0;
                    state<=BLEND;
                end
                BLEND:begin
                    // Keep the multiply signed. An unsigned ternary zero would
                    // zero-extend a negative difference during the wet ramp.
                    if(ready_q && mix_level!=0)
                        blend_product<=wet_dry_difference*$signed({1'b0,mix_level});
                    else blend_product<=0;
                    state<=PUBLISH;
                end
                PUBLISH:begin
                    out_sample<=(mix_level==0)?dry_q:blended_value[15:0];
                    out_valid<=1;state<=IDLE;
                end
                default:begin state<=IDLE;overrun<=1;end
            endcase
        end
    end
// synthesis translate_off
`ifndef SYNTHESIS
    initial begin
        if(BUFFER_BITS<2 || BUFFER_BITS>15 || RAMP_BITS<1 || RAMP_BITS>12 ||
           DEPTH_SAMPLES<0 || BASE_DELAY_SAMPLES-DEPTH_SAMPLES<1 ||
           READY_SAMPLES>=BUFFER_SIZE || BASE_DELAY_SAMPLES+DEPTH_SAMPLES>32766)
            $fatal(1,"Invalid audio_vibrato delay/ramp parameters");
    end
`endif
// synthesis translate_on
endmodule
`default_nettype wire
