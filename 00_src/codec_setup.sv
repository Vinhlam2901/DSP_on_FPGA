
// Single-clock 12.288 MHz system. I2C_DIV=16 gives approximately 361.4 kHz SCL.
module codec_setup #(
    parameter integer I2C_DIV = 16
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start_cfg,
    output logic cfg_done,
    output logic cfg_error,
    output logic cfg_busy,
    inout  tri   i2c_sda,
    output wire  i2c_scl
);
    logic        send_start_i2c;
    logic [15:0] cf_data;
    logic        i2c_busy;
    logic        i2c_done;
    logic        ack_error;
    logic [3:0]  reg_index_dbg;

    codec_config_by_i2c u_cfg (
        .clk_i2c          (clk),
        .rst_ni           (rst_n),
        .en_i             (1'b1),
        .start_cf_i       (start_cfg),
        .i2c_busy_i       (i2c_busy),
        .i2c_done_i       (i2c_done),
        .ack_error_i      (ack_error),
        .send_start_i2c_o (send_start_i2c),
        .cf_data_o        (cf_data),
        .cf_done_o        (cfg_done),
        .cf_error_o       (cfg_error),
        .cf_busy_o        (cfg_busy),
        .cf_reg_index_o   (reg_index_dbg)
    );

    i2c_master #(.DIV(I2C_DIV)) u_i2c (
        .clk         (clk),
        .reset_n     (rst_n),
        .start_pulse (send_start_i2c),
        .dev_addr    (7'h1A),
        .data_in     (cf_data),
        .busy        (i2c_busy),
        .done        (i2c_done),
        .ack_error   (ack_error),
        .i2c_sda     (i2c_sda),
        .i2c_scl     (i2c_scl)
    );
endmodule

