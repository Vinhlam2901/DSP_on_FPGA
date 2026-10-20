
module codec_config_by_i2c (
    input  logic        clk_i2c,
    input  logic        rst_ni,
    input  logic        en_i,
    input  logic        start_cf_i,
    input  logic        i2c_busy_i,
    input  logic        i2c_done_i,
    input  logic        ack_error_i,
    output logic        send_start_i2c_o,
    output logic [15:0] cf_data_o,
    output logic        cf_done_o,
    output logic        cf_error_o,
    output logic        cf_busy_o,
    output logic [3:0]  cf_reg_index_o
);
    // Playback-only sequence. OUTPD is kept off while configuring and
    // enabled only after the digital audio interface has been activated.
    localparam integer N_REGS = 10;

    typedef enum logic [1:0] {READY, ISSUE_WRITE, WAIT_WRITE} state_t;
    state_t state;
    logic [3:0] reg_index;
    logic start_cf_d;
    wire start_rise = start_cf_i & ~start_cf_d;

    assign cf_reg_index_o = reg_index;
    assign cf_busy_o = (state != READY);

    always_comb begin
        unique case (reg_index)
            4'd0: cf_data_o = 16'h1E00; // R15 software reset
            4'd1: cf_data_o = 16'h0C77; // R6 playback prep: outputs off, DAC on, ADC/mic/line off
            4'd2: cf_data_o = 16'h0479; // R2 left headphone volume 0 dB
            4'd3: cf_data_o = 16'h0679; // R3 right headphone volume 0 dB
            4'd4: cf_data_o = 16'h0812; // R4 DAC selected, mic muted, bypass/sidetone off
            4'd5: cf_data_o = 16'h0A00; // R5 de-emphasis off, DAC soft mute off
            4'd6: cf_data_o = 16'h0E0A; // R7 I2S, 24-bit, codec slave
            4'd7: cf_data_o = 16'h1000; // R8 normal mode, 48 kHz @ 12.288 MHz
            4'd8: cf_data_o = 16'h1201; // R9 ACTIVE=1
            4'd9: cf_data_o = 16'h0C67; // R6 enable outputs; keep unused ADC/mic/line/oscillator off
            default: cf_data_o = 16'h0000;
        endcase
    end

    always_ff @(posedge clk_i2c or negedge rst_ni) begin
        if (!rst_ni) begin
            state            <= READY;
            reg_index        <= 4'd0;
            start_cf_d       <= 1'b0;
            send_start_i2c_o <= 1'b0;
            cf_done_o        <= 1'b0;
            cf_error_o       <= 1'b0;
        end else begin
            start_cf_d       <= start_cf_i;
            send_start_i2c_o <= 1'b0;

            if (en_i) begin
                unique case (state)
                    READY: begin
                        if (start_rise && !i2c_busy_i) begin
                            reg_index  <= 4'd0;
                            cf_done_o  <= 1'b0;
                            cf_error_o <= 1'b0;
                            state      <= ISSUE_WRITE;
                        end
                    end

                    ISSUE_WRITE: begin
                        if (!i2c_busy_i) begin
                            send_start_i2c_o <= 1'b1;
                            state <= WAIT_WRITE;
                        end
                    end

                    WAIT_WRITE: begin
                        if (i2c_done_i) begin
                            if (ack_error_i) begin
                                // Sticky failure status until a new accepted start/reset.
                                cf_error_o <= 1'b1;
                                cf_done_o  <= 1'b0;
                                state      <= READY;
                            end else if (reg_index == N_REGS-1) begin
                                // Sticky success status; codec setup and audio logic now share the 12.288 MHz domain.
                                cf_done_o  <= 1'b1;
                                cf_error_o <= 1'b0;
                                state      <= READY;
                            end else begin
                                reg_index <= reg_index + 1'b1;
                                state     <= ISSUE_WRITE;
                            end
                        end
                    end

                    default: begin
                        state      <= READY;
                        cf_done_o  <= 1'b0;
                        cf_error_o <= 1'b1;
                    end
                endcase
            end
        end
    end
endmodule

