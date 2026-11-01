`timescale 1ns/1ps
`default_nettype none
// Same sample-boundary envelope as the two supplied ADSRs. Exact unsigned
// division runs for 32 clocks after a transition instead of using DSPs.
// The next sample must be at least 33 clocks later; this core requires 84.
module selectable_adsr_env #(
    parameter integer ATTACK_SAMPLES=98,
    parameter integer DECAY_SAMPLES=195312,
    parameter integer RELEASE_SAMPLES=7324,
    parameter [15:0] SUSTAIN_LEVEL=16'd0,
    parameter integer GUITAR_ATTACK_SAMPLES=49,
    parameter integer GUITAR_DECAY_SAMPLES=146484,
    parameter integer GUITAR_RELEASE_SAMPLES=2441,
    parameter [15:0] GUITAR_SUSTAIN_LEVEL=16'd0
)(
    input wire clk,rst_n,sample_ce,gate,timbre_select,
    output wire [15:0] envelope,
    output wire [2:0] state_dbg
);
    localparam [2:0] IDLE=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
    localparam [31:0] PEAK_FP=32'hffff0000;
    localparam [31:0] P_SUSTAIN={SUSTAIN_LEVEL,16'd0};
    localparam [31:0] G_SUSTAIN={GUITAR_SUSTAIN_LEVEL,16'd0};
    localparam [31:0] P_DECAY_RAW=(PEAK_FP-P_SUSTAIN)/DECAY_SAMPLES;
    localparam [31:0] G_DECAY_RAW=(PEAK_FP-G_SUSTAIN)/GUITAR_DECAY_SAMPLES;
    localparam [31:0] P_DECAY_STEP=P_DECAY_RAW==0 ? 32'd1:P_DECAY_RAW;
    localparam [31:0] G_DECAY_STEP=G_DECAY_RAW==0 ? 32'd1:G_DECAY_RAW;
    wire [31:0] attack_count=timbre_select ? GUITAR_ATTACK_SAMPLES:ATTACK_SAMPLES;
    wire [31:0] decay_count=timbre_select ? GUITAR_DECAY_SAMPLES:DECAY_SAMPLES;
    wire [31:0] release_count=timbre_select ? GUITAR_RELEASE_SAMPLES:RELEASE_SAMPLES;
    wire [31:0] sustain_fp=timbre_select ? G_SUSTAIN:P_SUSTAIN;
    wire [31:0] decay_step=timbre_select ? G_DECAY_STEP:P_DECAY_STEP;
    reg [2:0] state;
    reg [31:0] env_fp,sample_count,attack_step_fp,release_step_fp;
    reg [31:0] div_quotient,div_denominator;
    reg [32:0] div_remainder;
    reg [5:0] div_left;
    reg div_is_release;
    wire [32:0] trial={div_remainder[31:0],div_quotient[31]};
    wire take_bit=trial>={1'b0,div_denominator};
    wire [31:0] quotient_next={div_quotient[30:0],take_bit};
    assign envelope=env_fp[31:16];
    assign state_dbg=state;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;env_fp<=0;sample_count<=0;
            attack_step_fp<=1;release_step_fp<=1;
            div_quotient<=0;div_denominator<=1;div_remainder<=0;
            div_left<=0;div_is_release<=0;
        end else begin
            if(div_left!=0) begin
                div_remainder<=take_bit ? trial-{1'b0,div_denominator}:trial;
                div_quotient<=quotient_next;
                div_left<=div_left-1'b1;
                if(div_left==1) begin
                    if(div_is_release)
                        release_step_fp<=quotient_next==0 ? 32'd1:quotient_next;
                    else attack_step_fp<=quotient_next==0 ? 32'd1:quotient_next;
                end
            end
            if(sample_ce) begin
                if(!gate && (state==ATTACK || state==DECAY || state==SUSTAIN)) begin
                    state<=RELEASE;sample_count<=0;
                    div_quotient<=env_fp;div_denominator<=release_count;
                    div_remainder<=0;div_left<=32;div_is_release<=1;
                end else if(gate && state==RELEASE) begin
                    state<=ATTACK;sample_count<=0;
                    div_quotient<=PEAK_FP-env_fp;div_denominator<=attack_count;
                    div_remainder<=0;div_left<=32;div_is_release<=0;
                end else case(state)
                    IDLE: begin
                        env_fp<=0;sample_count<=0;
                        if(gate) begin
                            state<=ATTACK;
                            div_quotient<=PEAK_FP-env_fp;div_denominator<=attack_count;
                            div_remainder<=0;div_left<=32;div_is_release<=0;
                        end
                    end
                    ATTACK: begin
                        if(sample_count==attack_count-1'b1) begin
                            env_fp<=PEAK_FP;sample_count<=0;state<=DECAY;
                        end else begin
                            sample_count<=sample_count+1'b1;
                            env_fp<=(PEAK_FP-env_fp)<=attack_step_fp ?
                                PEAK_FP:env_fp+attack_step_fp;
                        end
                    end
                    DECAY: begin
                        if(sample_count==decay_count-1'b1) begin
                            env_fp<=sustain_fp;sample_count<=0;state<=SUSTAIN;
                        end else begin
                            sample_count<=sample_count+1'b1;
                            env_fp<=(env_fp-sustain_fp)<=decay_step ?
                                sustain_fp:env_fp-decay_step;
                        end
                    end
                    SUSTAIN: begin env_fp<=sustain_fp;sample_count<=0;end
                    RELEASE: begin
                        if(sample_count==release_count-1'b1) begin
                            env_fp<=0;sample_count<=0;state<=IDLE;
                        end else begin
                            sample_count<=sample_count+1'b1;
                            env_fp<=env_fp<=release_step_fp ? 32'd0:env_fp-release_step_fp;
                        end
                    end
                    default: begin
                        state<=IDLE;env_fp<=0;sample_count<=0;
                        attack_step_fp<=1;release_step_fp<=1;
                    end
                endcase
            end
        end
    end
    // synthesis translate_off
    initial begin
        if(ATTACK_SAMPLES<1 || DECAY_SAMPLES<1 || RELEASE_SAMPLES<1 ||
           GUITAR_ATTACK_SAMPLES<1 || GUITAR_DECAY_SAMPLES<1 || GUITAR_RELEASE_SAMPLES<1)
            $fatal(1,"Envelope sample counts must be positive");
    end
    always @(posedge clk)
        if(rst_n && sample_ce && div_left!=0)
            $fatal(1,"ADSR division still busy at next sample request");
    // synthesis translate_on
endmodule
`default_nettype wire
