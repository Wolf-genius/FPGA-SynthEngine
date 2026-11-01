`timescale 1ns/1ps
`default_nettype none
// Piano: original 20-partial algorithm. Guitar: supplied fractional string model.
// One shared signed multiplier per voice, scheduled over 83 system clocks.
// Accept requests >=84 clocks apart (board audio interval is 1024 clocks).
module dual_timbre_voice #(
    parameter integer VOICE_INDEX=0,
    parameter integer ATTACK_SAMPLES=98,
    parameter integer DECAY_SAMPLES=195312,
    parameter integer RELEASE_SAMPLES=7324,
    parameter [15:0] SUSTAIN_LEVEL=16'd0,
    parameter integer GUITAR_ATTACK_SAMPLES=49,
    parameter integer GUITAR_DECAY_SAMPLES=146484,
    parameter integer GUITAR_RELEASE_SAMPLES=2441,
    parameter [15:0] GUITAR_SUSTAIN_LEVEL=16'd0,
    parameter integer GUITAR_CONTINUOUS_PRESSURE=0,
    parameter [15:0] GUITAR_LOOP_GAIN=16'd65500
)(
    input wire clk,rst_n,sample_ce,gate,timbre_select,
    input wire [31:0] phase_step,
    input wire [15:0] gain,
    output reg signed [15:0] sample,
    output reg sample_valid,
    output wire [15:0] envelope_dbg,
    output wire [2:0] state_dbg,
    output wire [15:0] held_gain_dbg
);
    selectable_adsr_env #(.ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .RELEASE_SAMPLES(RELEASE_SAMPLES),.SUSTAIN_LEVEL(SUSTAIN_LEVEL),
        .GUITAR_ATTACK_SAMPLES(GUITAR_ATTACK_SAMPLES),
        .GUITAR_DECAY_SAMPLES(GUITAR_DECAY_SAMPLES),
        .GUITAR_RELEASE_SAMPLES(GUITAR_RELEASE_SAMPLES),
        .GUITAR_SUSTAIN_LEVEL(GUITAR_SUSTAIN_LEVEL)) u_adsr (
        .clk(clk),.rst_n(rst_n),.sample_ce(sample_ce),.gate(gate),
        .timbre_select(timbre_select),.envelope(envelope_dbg),.state_dbg(state_dbg));
    reg [15:0] held_gain;
    reg [15:0] g_strike_gain;
    assign held_gain_dbg=timbre_select ? g_strike_gain:held_gain;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) held_gain<=0;
        else if(gate) held_gain<=gain;
        else if(state_dbg==0) held_gain<=0;

    reg signed [15:0] sine_rom [0:1023];
    reg [15:0] amp_rom [0:511];
    reg [31:0] ratio_rom [0:31];
    initial begin
        $readmemh("tables/piano_sine.hex",sine_rom);
        if(VOICE_INDEX==0) begin $readmemh("tables/piano_C4_amp.hex",amp_rom);$readmemh("tables/piano_C4_ratio.hex",ratio_rom);end
        else if(VOICE_INDEX==1) begin $readmemh("tables/piano_D4_amp.hex",amp_rom);$readmemh("tables/piano_D4_ratio.hex",ratio_rom);end
        else if(VOICE_INDEX==2) begin $readmemh("tables/piano_E4_amp.hex",amp_rom);$readmemh("tables/piano_E4_ratio.hex",ratio_rom);end
        else if(VOICE_INDEX==3) begin $readmemh("tables/piano_F4_amp.hex",amp_rom);$readmemh("tables/piano_F4_ratio.hex",ratio_rom);end
        else if(VOICE_INDEX==4) begin $readmemh("tables/piano_G4_amp.hex",amp_rom);$readmemh("tables/piano_G4_ratio.hex",ratio_rom);end
        else if(VOICE_INDEX==5) begin $readmemh("tables/piano_A4_amp.hex",amp_rom);$readmemh("tables/piano_A4_ratio.hex",ratio_rom);end
        else if(VOICE_INDEX==6) begin $readmemh("tables/piano_B4_amp.hex",amp_rom);$readmemh("tables/piano_B4_ratio.hex",ratio_rom);end
        else begin $readmemh("tables/piano_C5_amp.hex",amp_rom);$readmemh("tables/piano_C5_ratio.hex",ratio_rom);end
    end
    reg [31:0] phases [0:19];
    reg [23:0] age;
    reg previous_gate;
    wire note_on=gate && !previous_gate;
    wire [23:0] read_age=note_on ? 24'd0 : age;
    reg [3:0] frame;
    reg [15:0] fraction;
    integer j;
    // Log-spaced knots: 0,128,256,512,... samples. No variable divider.
    always @* begin
        frame=0;fraction=read_age[6:0]<<9;
        for(j=1;j<15;j=j+1) begin
            if(read_age >= (24'd1 << (j+6))) begin
                frame=j;
                fraction=(({16'd0,read_age}-(40'd1 << (j+6))) << 16) >> (j+6);
            end
        end
        if(read_age >= (24'd1<<21)) begin frame=15;fraction=0;end
    end
    reg busy,reset_phase;
    reg [2:0] stage;
    reg [4:0] harmonic;
    reg [3:0] frame_saved;
    reg [15:0] fraction_saved,gain_saved,env_saved;
    reg [31:0] step_saved,phase_increment;
    reg [15:0] amp_a,amp_b;
    reg signed [15:0] carrier;
    reg signed [31:0] accumulator;
    reg signed [31:0] mul_a,mul_b;
    wire signed [63:0] mul_product /* synthesis syn_dspstyle="dsp" */;
    assign mul_product=mul_a*mul_b;
    wire signed [63:0] interpolated=$signed({1'b0,amp_a})+(mul_product>>>16);
    wire signed [63:0] partial_scaled=mul_product>>>15;
    wire signed [31:0] next_sum=accumulator+partial_scaled[31:0];
    wire [31:0] phase_read=reset_phase ? 32'd0 : phases[harmonic];
    wire [3:0] next_frame=(frame_saved==15) ? 4'd15 : frame_saved+1'b1;
    wire signed [63:0] final_scaled=mul_product>>>16;
    integer k;
    wire g_pitch_supported;
    wire [9:0] g_pitch_delay;
    wire [15:0] g_pitch_fraction;
    guitar_pitch_lut g_pitch(.phase_step(phase_step),.supported(g_pitch_supported),
        .delay_integer(g_pitch_delay),.fraction(g_pitch_fraction));
    localparam [15:0] g_SEED=16'hace1 ^ (VOICE_INDEX*16'h1234);
    function [15:0] g_advance_noise;
        input [15:0] value;
        begin g_advance_noise={value[14:0],value[15]^value[13]^value[12]^value[10]};end
    endfunction
    reg g_previous_gate;
    wire g_onset=gate && !g_previous_gate;
    reg [15:0] g_noise_state;
    wire [15:0] g_noise_word=g_onset ? g_SEED : g_noise_state;
    wire signed [15:0] g_noise_value=$signed(g_noise_word)>>>1;
    reg signed [15:0] g_previous_noise;
    wire signed [16:0] g_excitation_sum=$signed({g_noise_value[15],g_noise_value})+
        (g_onset ? 17'sd0 : $signed({g_previous_noise[15],g_previous_noise}));

    reg signed [15:0] g_delay_mem [0:1023]; // Never reset the RAM array.
    reg [9:0] g_write_pos;
    reg [10:0] g_filled;
    wire [9:0] g_selected_pos=g_onset ? 10'd0 : g_write_pos;
    reg [9:0] g_saved_pos,g_addr0,g_addr1;
    reg [15:0] g_fraction_saved,g_gain_saved,g_env_saved;
    reg g_fill_saved,g_supported_saved;
    reg [6:0] g_cycle;
    reg signed [15:0] g_tap0,g_tap1,g_excitation_saved;
    reg signed [31:0] g_interpolated,g_previous_interp,g_y,g_previous_y;
    reg signed [15:0] g_pending;
    wire signed [31:0] g_average=(g_interpolated+g_previous_interp)>>>1;
    wire signed [31:0] g_bright=g_y+((g_y-g_previous_y)>>>2);
    wire signed [63:0] g_result_scaled=mul_product>>>16;
    // Both algorithms drive the same mul_a/mul_b registers and product.
    // Timbre changes only while the complete core is quiet and idle.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sample<=0;sample_valid<=0;busy<=0;stage<=0;harmonic<=0;
            age<=0;previous_gate<=0;reset_phase<=0;frame_saved<=0;fraction_saved<=0;
            gain_saved<=0;env_saved<=0;step_saved<=0;phase_increment<=0;
            amp_a<=0;amp_b<=0;carrier<=0;accumulator<=0;mul_a<=0;mul_b<=0;
            for(k=0;k<20;k=k+1) phases[k]<=0;
            g_previous_gate<=0;g_strike_gain<=0;
            g_noise_state<=g_SEED;g_previous_noise<=0;g_write_pos<=0;g_filled<=0;
            g_saved_pos<=0;g_addr0<=0;g_addr1<=0;g_fraction_saved<=0;g_gain_saved<=0;g_env_saved<=0;
            g_fill_saved<=1;g_supported_saved<=0;g_cycle<=0;g_tap0<=0;g_tap1<=0;
            g_excitation_saved<=0;g_interpolated<=0;g_previous_interp<=0;g_y<=0;g_previous_y<=0;
            g_pending<=0;
        end else begin
            sample_valid<=0;
            if(timbre_select) begin
            if(sample_ce && !busy)begin
                busy<=1;g_cycle<=0;g_previous_gate<=gate;
                g_saved_pos<=g_selected_pos;
                g_addr0<=g_selected_pos-g_pitch_delay;
                g_addr1<=g_selected_pos-g_pitch_delay-10'd1;
                g_fraction_saved<=g_pitch_fraction;g_supported_saved<=g_pitch_supported;
                g_fill_saved<=g_onset || (g_filled<=g_pitch_delay);
                if(!g_pitch_supported)g_filled<=0;
                else if(g_onset)g_filled<=1;
                else if(g_filled<1024)g_filled<=g_filled+1'b1;
                g_write_pos<=g_selected_pos+1'b1;
                g_noise_state<=g_advance_noise(g_noise_word);
                g_previous_noise<=g_noise_value;
                g_excitation_saved<=g_excitation_sum>>>1;
                if(g_onset)begin g_strike_gain<=gain;g_previous_interp<=0;g_previous_y<=0;end
                else if(GUITAR_CONTINUOUS_PRESSURE && gate)g_strike_gain<=gain;
                else if(state_dbg==0 && !gate)g_strike_gain<=0;
                g_gain_saved<=GUITAR_CONTINUOUS_PRESSURE ? (gate ? gain : g_strike_gain) :
                            (g_onset ? gain : g_strike_gain);
            end else if(busy)begin
                g_cycle<=g_cycle+1'b1;
                case(g_cycle)
                // Schedule the two RAM reads and write on different clocks.
                0:begin g_tap0<=g_delay_mem[g_addr0];g_env_saved<=envelope_dbg;end
                1:g_tap1<=g_delay_mem[g_addr1];
                2:begin
                    mul_a<=$signed({{16{g_tap1[15]}},g_tap1})-$signed({{16{g_tap0[15]}},g_tap0});
                    mul_b<=$signed({1'b0,g_fraction_saved});
                end
                3:g_interpolated<=$signed({{16{g_tap0[15]}},g_tap0})+(mul_product>>>16);
                4:begin mul_a<=g_average;mul_b<=$signed({1'b0,GUITAR_LOOP_GAIN});end
                5:g_y<=!g_supported_saved ? 32'sd0 :
                       (g_fill_saved ? {{16{g_excitation_saved[15]}},g_excitation_saved} : mul_product>>>16);
                6:begin
                    g_delay_mem[g_saved_pos]<=g_y[15:0];
                    g_previous_interp<=(!g_supported_saved || g_fill_saved) ? 0 : g_interpolated;
                    g_previous_y<=g_y;
                    mul_a<=g_supported_saved ? g_bright : 32'sd0;
                    mul_b<=$signed({1'b0,g_env_saved});
                end
                7:begin mul_a<=mul_product>>>16;mul_b<=$signed({1'b0,g_gain_saved});end
                8:g_pending<=(g_result_scaled>32767) ? 16'sh7fff :
                           (g_result_scaled < -32768) ? 16'sh8000 : g_result_scaled[15:0];
                82:begin sample<=g_pending;sample_valid<=1;busy<=0;end
                default:begin end
                endcase
            end
            end else begin
            if(sample_ce && !busy) begin
                busy<=1;stage<=0;harmonic<=0;accumulator<=0;
                frame_saved<=frame;fraction_saved<=fraction;step_saved<=phase_step;
                gain_saved<=gate ? gain : held_gain;reset_phase<=note_on;
                previous_gate<=gate;
                if(note_on) age<=1;
                else if(age!=24'hffffff) age<=age+1'b1;
            end else if(busy) begin
                case(stage)
                0: begin
                    // Synchronous ROM reads; two amplitude ports, one carrier port.
                    amp_a<=amp_rom[{frame_saved,harmonic}];
                    amp_b<=amp_rom[{next_frame,harmonic}];
                    mul_a<=$signed(step_saved);mul_b<=$signed(ratio_rom[harmonic]);
                    if(harmonic==0) env_saved<=envelope_dbg;
                    stage<=1;
                end
                1: begin
                    phase_increment<=mul_product[47:16];
                    carrier<=sine_rom[phase_read[31:22]];
                    mul_a<=$signed({1'b0,amp_b})-$signed({1'b0,amp_a});
                    mul_b<=$signed({1'b0,fraction_saved});stage<=2;
                end
                2: begin
                    mul_a<={{16{carrier[15]}},carrier};mul_b<=interpolated[31:0];stage<=3;
                end
                3: begin
                    accumulator<=next_sum;
                    phases[harmonic]<=phase_read+phase_increment;
                    if(harmonic==19) stage<=4;
                    else begin harmonic<=harmonic+1'b1;stage<=0;end
                end
                4: begin mul_a<=accumulator;mul_b<=$signed({1'b0,env_saved});stage<=5;end
                5: begin mul_a<=mul_product>>>16;mul_b<=$signed({1'b0,gain_saved});stage<=6;end
                6: begin
                    sample <= (final_scaled>32767) ? 16'sh7fff :
                              (final_scaled < -32768) ? 16'sh8000 : final_scaled[15:0];
                    sample_valid<=1;busy<=0;stage<=0;
                end
                default: begin busy<=0;stage<=0;end
                endcase
            end
            end
        end
    end
endmodule
`default_nettype wire
