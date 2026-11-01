`timescale 1ns/1ps
`default_nettype none
// 50 MHz / 1024 = 48828.125 Hz. Voice0 occupies the LOW 32 bits.
// Recalculate all words if the audio sample rate changes.
module note_steps(output wire [255:0] phase_steps);
    assign phase_steps[0 +: 32] = 32'd23012828; // C4, 261.625565 Hz
    assign phase_steps[32 +: 32] = 32'd25831026; // D4, 293.664768 Hz
    assign phase_steps[64 +: 32] = 32'd28994347; // E4, 329.627557 Hz
    assign phase_steps[96 +: 32] = 32'd30718440; // F4, 349.228231 Hz
    assign phase_steps[128 +: 32] = 32'd34480283; // G4, 391.995436 Hz
    assign phase_steps[160 +: 32] = 32'd38702809; // A4, 440.000000 Hz
    assign phase_steps[192 +: 32] = 32'd43442435; // B4, 493.883301 Hz
    assign phase_steps[224 +: 32] = 32'd46025656; // C5, 523.251131 Hz
endmodule
`default_nettype wire
