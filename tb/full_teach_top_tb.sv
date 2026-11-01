`timescale 1ns/1ps
// Actual top: external UART, MCP3208 SPI responses, physical buttons,
// external I2S decoder and live LCD pins. No force of internal controls.
module full_teach_top_tb;
    localparam CPT=16;
    reg clk=0,rst_n=0,adc_miso=0,bt_rx=1,key1_n=1,key2_n=1;
    always #10 clk=~clk;
    wire adc_cs_n,adc_sclk,adc_mosi,bclk,ws,din,bt_tx;
    wire lcd_sck,lcd_sda,lcd_cs_n,lcd_rs,lcd_res_n;
    wire [7:0] led;
    eight_key_instrument_display_top #(
        .BT_CLKS_PER_BIT(CPT),.VIBRATO_RAMP_BITS(4),
        .TEACH_TICK_CYCLES(1024),.TEACH_FRAME_TIMEOUT_MS(1000),
        .DEBOUNCE_CYCLES(5),
        .LCD_SPI_HALF_CYCLES(1),.LCD_RESET_LOW_CYCLES(4),
        .LCD_RESET_HIGH_CYCLES(5),.LCD_SLEEP_OUT_CYCLES(6),.LCD_PAGE_HOLD_CYCLES(20),
        .ATTACK_SAMPLES(4),.DECAY_SAMPLES(6),.RELEASE_SAMPLES(8),.SUSTAIN_LEVEL(16'd42598),
        .GUITAR_ATTACK_SAMPLES(4),.GUITAR_DECAY_SAMPLES(6),
        .GUITAR_RELEASE_SAMPLES(8),.GUITAR_SUSTAIN_LEVEL(16'd42598)
    ) dut(.*);
    task clocks(input integer n);repeat(n) @(negedge clk);endtask
    task send_byte(input [7:0] b);
        integer k;
        begin bt_rx=0;clocks(CPT);
            for(k=0;k<8;k=k+1) begin bt_rx=b[k];clocks(CPT);end
            bt_rx=1;clocks(CPT);
        end
    endtask
    task line(input string text);
        integer k;
        begin for(k=0;k<text.len();k=k+1) send_byte(text[k]);send_byte(10);clocks(8);end
    endtask
    task press_button(input integer which);
        begin
            if(which==1) key1_n=0;else key2_n=0;
            clocks(12);
            if(which==1) key1_n=1;else key2_n=1;
            clocks(12);
        end
    endtask
    // Real scanner command decoding; the test changes external sensor values.
    reg [7:0] raw_keys=0;
    reg [23:0] command_word=0;
    reg [11:0] raw_value=0;
    integer rises=0,transactions=0,pressure_frames=0,selected_channel;
    always @(negedge adc_cs_n) if(dut.run_rst_n) begin
        rises=0;command_word=0;raw_value=0;adc_miso=0;
    end
    always @(posedge adc_sclk) if(dut.run_rst_n && !adc_cs_n) begin
        command_word={command_word[22:0],adc_mosi};rises=rises+1;
        if(rises==10) begin
            selected_channel=command_word[2:0];
            if(selected_channel!=transactions%8) $fatal(1,"ADC channel ordering");
            raw_value=raw_keys[selected_channel]?12'd3840:12'd0;
        end
    end
    always @(negedge adc_sclk) if(dut.run_rst_n && !adc_cs_n) begin
        #200;adc_miso=(rises>=12 && rises<=23)?raw_value[23-rises]:1'b0;
    end
    always @(posedge adc_cs_n) if(dut.run_rst_n) begin
        if(rises!=24 || command_word!==(24'h060000|((transactions%8)<<14)))
            $fatal(1,"ADC SPI transaction");
        transactions=transactions+1;adc_miso=0;
    end
    always @(negedge dut.run_rst_n) begin transactions=0;rises=0;adc_miso=0;end
    always @(posedge dut.pressure_valid) pressure_frames=pressure_frames+1;
    integer i,lcd_edges=0,checks=0;
    integer progress_file;
    initial progress_file=$fopen("sim/top_progress.txt","w");
    always @(negedge clk)if(checks>0 && checks%100000==0)begin
     $fdisplay(progress_file,"checks=%0d state=%0d step=%0d raw=%h timbre=%0d",checks,dut.teach_state,dut.lesson_step,raw_keys,dut.timbre_select);$fflush(progress_file);
    end
    reg[7:0] prior_held=0,pre_gate;reg pre_valid;
    reg[7:0] upload[0:4095];integer upload_bytes,fh,unused;
    always @(posedge clk)begin
     pre_valid=dut.controls_valid;pre_gate=dut.gate;#3;
     if(dut.run_rst_n)begin
      if(dut.alignment_error||dut.underrun_count||dut.discarded_count||dut.timeout_count||dut.tx_overflow||dut.teach_fault||dut.vibrato_overrun)$fatal(1,"top fault");
      if(dut.gate!==dut.pressure_gate || dut.key_gain!==dut.pressure_gain || dut.controls_valid!==dut.pressure_valid)$fatal(1,"Bluetooth changed physical audio source");
      if(pre_valid)prior_held=pre_gate;
      if(dut.display.mixed_sample!==dut.mixed_sample || dut.display.mixed_valid!==dut.mixed_valid)$fatal(1,"spectrum must observe processed audio");
      if(dut.audio.buffer.mixed_data!==dut.mixed_sample || dut.audio.buffer.mixed_valid!==dut.mixed_valid)$fatal(1,"I2S must observe processed audio");
      if(dut.display.held!==prior_held)$fatal(1,"screen held keys");checks=checks+1;
     end else prior_held=0;
    end
    always @(posedge lcd_sck)if(dut.run_rst_n && !lcd_cs_n)lcd_edges=lcd_edges+1;
    // Decode real I2S edges and compare every channel word with the preceding
    // accepted PCM sample; no inspection of the transmitter's shift register.
    reg [15:0] mixes[0:16383];
    reg [15:0] received_word=0;
    integer mix_count=0,slot=0,bit_number=0,nonzero_slots=0;
    integer previous_audio_samples=0;
    time last_bclk=0;
    always @(negedge dut.run_rst_n) begin
        mix_count=0;slot=0;bit_number=0;received_word=0;last_bclk=0;
    end
    always @(posedge dut.mixed_valid) begin #1;mixes[mix_count]=dut.mixed_sample;mix_count=mix_count+1;end
    always @(posedge bclk) if(dut.run_rst_n) begin
        if(last_bclk && $time-last_bclk!=320) $fatal(1,"I2S bit period changed");
        last_bclk=$time;
        if(ws!==(slot%2)) $fatal(1,"I2S channel polarity");
        if(bit_number==0 && din!==0) $fatal(1,"I2S one-bit delay");
        if(bit_number>=1 && bit_number<=16) received_word={received_word[14:0],din};
        if(bit_number>=17 && din!==0) $fatal(1,"I2S nonzero padding");
        if(bit_number==31) begin
            if(received_word!==(slot/2==0?16'd0:mixes[slot/2-1])) $fatal(1,"I2S sample word mismatch");
            if(received_word!=0) nonzero_slots=nonzero_slots+1;
            slot=slot+1;bit_number=0;received_word=0;
        end else bit_number=bit_number+1;
    end
    // Independent queue proves disabled FX is exact dry PCM, not merely a
    // transmitter self-comparison. The wet path must change both timbres.
    reg signed[15:0]dry_samples[0:16383];
    integer raw_count=0,effect_count=0,dry_checks=0,wet_checks=0,wet_changes=0,prior_wet;
    reg wet_piano=0,wet_guitar=0;
    always @(negedge dut.run_rst_n)begin raw_count=0;effect_count=0;end
    always @(posedge dut.synth_valid)begin #1;dry_samples[raw_count]=dut.synth_sample;raw_count=raw_count+1;end
    always @(posedge dut.mixed_valid)begin
     #2;if(effect_count>=raw_count)$fatal(1,"FX produced unsolicited sample");
     if(dut.vibrato.mix_level==0)begin
      if(dut.mixed_sample!==dry_samples[effect_count])$fatal(1,"disabled FX not bit-exact");
      dry_checks=dry_checks+1;
     end else if(dut.vibrato.mix_level==16)begin
      wet_checks=wet_checks+1;
      if(dut.mixed_sample!==dry_samples[effect_count])begin
       wet_changes=wet_changes+1;
       if(dut.timbre_select)wet_guitar=1;else wet_piano=1;
      end
     end
     effect_count=effect_count+1;
    end
    integer uart_file,n;
    reg [7:0] got;
    always @(negedge bt_tx) if(dut.run_rst_n) begin
        clocks(CPT/2);if(bt_tx!==0) $fatal(1,"UART start bit");
        for(n=0;n<8;n=n+1) begin clocks(CPT);got[n]=bt_tx;end
        clocks(CPT);if(bt_tx!==1) $fatal(1,"UART stop bit");
        $fwrite(uart_file,"%c",got);
    end
    initial begin
     fh=$fopen("sim/full_count.txt","r");unused=$fscanf(fh,"%d",upload_bytes);$fclose(fh);
     $readmemh("sim/full_upload.hex",upload,0,upload_bytes-1);
     uart_file=$fopen("sim/full_uart.txt","wb");
     clocks(6);rst_n=1;wait(pressure_frames>=2);clocks(5);
     if(dut.gate!=0||led!=0)$fatal(1,"boot");line("PING");
     raw_keys=1;wait(dut.pressure_gate==1);wait(nonzero_slots>10);
     line("VIBSTAT");line("VIBON");line("VIBSTAT");
     wait(dut.vibrato.wet_amount==16);prior_wet=wet_checks;wait(wet_checks>prior_wet+20);
     if(!dut.vibrato_enable||!wet_piano)$fatal(1,"Bluetooth piano vibrato");
     line("VIBOFF");wait(dut.vibrato.wet_amount==0);line("VIBSTAT");
     raw_keys=0;wait(dut.pressure_gate==0);wait(dut.states==0);clocks(2048);
     press_button(1);wait(dut.timbre_select==1);
     previous_audio_samples=nonzero_slots;raw_keys=4;wait(dut.pressure_gate==4);wait(nonzero_slots>previous_audio_samples+10);
     line("VIBON");wait(dut.vibrato.wet_amount==16);prior_wet=wet_checks;wait(wet_checks>prior_wet+20);
     if(!wet_guitar)$fatal(1,"Bluetooth guitar vibrato");line("VIBOFF");wait(dut.vibrato.wet_amount==0);
     raw_keys=0;wait(dut.pressure_gate==0);wait(dut.states==0);clocks(2048);
     press_button(2);wait(dut.octave_select==1);press_button(2);wait(dut.octave_select==2);press_button(2);wait(dut.octave_select==0);
     press_button(1);wait(dut.timbre_select==0);
     for(i=0;i<upload_bytes;i=i+1)send_byte(upload[i]);clocks(100);
     if(!dut.song_valid||dut.song_count!=4||led!=0)$fatal(1,"download commit");
     line("TEACH");wait(dut.teach_state==3);if(led!=128)$fatal(1,"must teach downloaded C5, not ROM C4");
     line("VIBON");line("VIBSTAT");
     if(!dut.teach_active||dut.lesson_step!=0||led!=128)$fatal(1,"FX command altered teaching");
     // Wrong physical CH0 produces sound but does not pass the C5 target.
     raw_keys=1;wait(dut.pressure_gate==1);clocks(50000);if(dut.lesson_step!=0)$fatal(1,"wrong advanced");
     raw_keys=0;wait(dut.pressure_gate==0);clocks(5);
     raw_keys=128;wait(dut.lesson_step==1);wait(dut.teach_state==3);clocks(2);
     if(led!=5||dut.pressure_gate!=128)$fatal(1,"next target must appear before release");
     clocks(100000);if(dut.lesson_step!=1)$fatal(1,"held first key skipped next target");
     // Change to the target chord without first observing an all-zero frame.
     raw_keys=5;wait(dut.lesson_step==2);wait(dut.teach_state==3);clocks(2);if(led!=1)$fatal(1,"first repeated note");
     raw_keys=1;clocks(150000);if(dut.lesson_step!=2)$fatal(1,"already held C4 accepted as a new press");
     raw_keys=0;wait(dut.pressure_gate==0);raw_keys=1;
     wait(dut.lesson_step==3);wait(dut.teach_state==3);clocks(2);if(led!=1)$fatal(1,"second repeated note");
     clocks(100000);if(dut.lesson_step!=3)$fatal(1,"long hold skipped second C4");
     raw_keys=0;wait(dut.pressure_gate==0);raw_keys=1;wait(dut.teach_done);
     if(dut.pressure_gate!=1)$fatal(1,"DONE must arrive before last key release");
     clocks(10000);line("VIBOFF");wait(dut.vibrato.wet_amount==0);line("STATUS");raw_keys=0;wait(dut.pressure_gate==0);
     line("TEACH");wait(dut.teach_state==3);raw_keys=128;wait(dut.pressure_gate==128);
     line("STOP");clocks(10);if(led!=0||dut.teach_active||dut.gate!=128)$fatal(1,"STOP must stop lesson but preserve physical sound");
     raw_keys=0;wait(dut.pressure_gate==0);line("TEACH");wait(dut.teach_state==3);clocks(10000);
     rst_n=0;clocks(6);if(led!=0||bt_tx!==1)$fatal(1,"reset outputs");
     rst_n=1;clocks(20);line("STATUS");line("TEACH");clocks(10000);
     if(dut.song_valid||dut.teach_active||led!=0||dut.vibrato_enable)$fatal(1,"reset valid song");
     if(nonzero_slots<100||lcd_edges<160000||pressure_frames<35||checks<1000000)$fatal(1,"coverage");
     if(!wet_piano||!wet_guitar||dry_checks<100||wet_changes<20)$fatal(1,"FX coverage");
     $display("PASS integrated pitch FX: dry_exact=%0d wet_samples=%0d wet_changed=%0d piano=%b guitar=%b",dry_checks,wet_checks,wet_changes,wet_piano,wet_guitar);
     $fclose(uart_file);$display("PASS full top UART->score RAM->real MCP3208 ADC pressure->press-to-advance teaching LEDs, held-repeat protection, piano/guitar/octave, PCM->external I2S words and LCD: frames=%0d checks=%0d slots=%0d LCDedges=%0d",pressure_frames,checks,nonzero_slots,lcd_edges);$finish;
    end
    initial begin #200000000;$fatal(1,"top timeout state=%0d addr=%0d",dut.teach_state,dut.lesson_step);end
endmodule
