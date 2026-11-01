`timescale 1ns/1ps
`default_nettype none
// One feature: download a score and tutor real pressure keys. Never drives audio.
module bluetooth_teach_control #(
 parameter integer CLKS_PER_BIT=5208,TICK_CYCLES=50000,FRAME_TIMEOUT_MS=10
)(
 input wire clk,rst_n,bt_rx,controls_valid,
 input wire [7:0] gate,
 output wire bt_tx,
 output wire [7:0] led,
 output wire active,done,fault,input_stale,loading,song_valid,
 output wire [8:0] song_count,
 output wire [7:0] lesson_step,target_mask,
 output wire [2:0] state,
 output wire vibrato_enable,
 output wire tx_overflow
);
 wire [7:0] rx_data;wire rx_valid,rx_error,cmd_valid,crc_present;
 wire [3:0] cmd;wire [8:0] count;wire [47:0] record;wire [15:0] crc_value,running_crc;
 wire start,stop,step_ready,step_valid,step_last,reply_valid;
 wire [7:0] step_mask;wire [15:0] duration;wire [4:0] reply_code;
 wire step_pass,wrong_press;
 uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver(
 .clk(clk),.rst_n(rst_n),.rx(bt_rx),.data(rx_data),.valid(rx_valid),.framing_error(rx_error));
 score_command_parser #(.ENABLE_LESSON_COMMANDS(1),.ENABLE_VIBRATO_COMMANDS(1)) parser(
 .clk(clk),.rst_n(rst_n),.rx_valid(rx_valid),.rx_error(rx_error),.rx_data(rx_data),
 .cmd_valid(cmd_valid),.cmd(cmd),.count(count),.record(record),.crc_present(crc_present),.crc_value(crc_value));
 download_score_store store(
 .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.count(count),.record(record),
 .crc_present(crc_present),.crc_value(crc_value),.teach_active(active),.teach_done(done),.teach_fault(fault),
 .lesson_addr(lesson_step),.loading(loading),.song_valid(song_valid),.song_count(song_count),
 .teach_start(start),.teach_stop(stop),.vibrato_enable(vibrato_enable),.step_ready(step_ready),.step_valid(step_valid),
 .step_last(step_last),.step_mask(step_mask),.step_duration_ms(duration),
 .reply_valid(reply_valid),.reply_code(reply_code),.running_crc(running_crc));
 teach_ctrl #(.TICK_CYCLES(TICK_CYCLES),.FRAME_TIMEOUT_MS(FRAME_TIMEOUT_MS)) teacher(
 .clk(clk),.rst_n(rst_n),.start(start),.stop(stop),.controls_valid(controls_valid),.gate(gate),
 .song_addr(lesson_step),.step_ready(step_ready),.step_valid(step_valid),.step_mask(step_mask),
 .step_duration_ms(duration),.step_last(step_last),.active(active),.done(done),.fault(fault),
 .target_mask(target_mask),.step_pass(step_pass),.wrong_press(wrong_press),.input_stale(input_stale),.state(state));
 led_driver lamps(.clk(clk),.rst_n(rst_n),.enable(active && !fault),
 .target_mask(target_mask),.brightness(8'd255),.led(led));
 score_reply_uart #(.CLKS_PER_BIT(CLKS_PER_BIT)) replies(
 .clk(clk),.rst_n(rst_n),.reply_valid(reply_valid),.reply_code(reply_code),.tx(bt_tx),.overflow_seen(tx_overflow));
endmodule
`default_nettype wire
