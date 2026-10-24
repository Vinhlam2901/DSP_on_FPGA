module DE10_Standard_golden_top  #(
  parameter int PHASE_WIDTH = 10,  // Số bit biểu diễn góc pha (2^8 = 256 mẫu góc)
  parameter int DATA_WIDTH = 24
)(
  input  logic        CLOCK_50,
  input  logic [3:0]  KEY,
  input  logic [9:0]  SW,
  output logic [9:0]  LEDR,
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
  // Audio I2C
  output logic        FPGA_I2C_SCLK,
  inout  wire         FPGA_I2C_SDAT,
  // Audio I2S
  output logic        AUD_XCK,
  output logic        AUD_BCLK,
  output logic        AUD_DACLRCK,
  output logic        AUD_DACDAT
);
  logic rst_n;
  assign rst_n = KEY[0];
  assign LEDR[9:4] = SW[9:4];
  // 1. Chống rung phím
  logic btn_down_tick, btn_up_tick, btn_step_tick;
  button_debouncer db_down (.clk(CLOCK_50), .rst_n(rst_n), .btn_in(KEY[1]), .btn_tick(btn_down_tick));
  button_debouncer db_up   (.clk(CLOCK_50), .rst_n(rst_n), .btn_in(KEY[2]), .btn_tick(btn_up_tick));
  button_debouncer db_step (.clk(CLOCK_50), .rst_n(rst_n), .btn_in(KEY[3]), .btn_tick(btn_step_tick));
  // 2. Logic điều khiển thông số
  localparam int MAX_FREQ  = 20000;
  localparam int MIN_FREQ  = 1;
  localparam int TW_1HZ    = 350; // Bước nhảy cho 12.288MHz
  // Cực đại dương 24-bit: 0111...111 = 24'h7FFFFF
  localparam signed [DATA_WIDTH-1:0] MAX_POS = (1 << (DATA_WIDTH - 1)) - 1; 
  // Cực đại âm 24-bit:   1000...000 = 24'h800000
  localparam signed [DATA_WIDTH-1:0] MAX_NEG = ~(MAX_POS);
  logic        start_cfg;
  logic        clk_12M;
  logic [1:0]  amp_ctrl;
  logic [1:0]  step_idx;
  logic [15:0] freq_val;
  logic [31:0] step_freq;
  logic [31:0] tuning_word;
  //================Amplitude Control===========================
  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      freq_val   <= 1000;
      amp_ctrl   <= 2'b11;
      step_idx   <= 2'b00;
      step_freq  <= 1;
    end else begin
      if (btn_step_tick) begin
        step_idx <= step_idx + 1;
        case (step_idx + 1)
          2'b00: step_freq <= 1;
          2'b01: step_freq <= 10;
          2'b10: step_freq <= 100;
          2'b11: step_freq <= 1000;
        endcase
      end
      if (btn_up_tick) begin
        if (SW[4]) begin
          if (freq_val + step_freq <= MAX_FREQ) freq_val <= freq_val + step_freq;
        end else if (~SW[4]) begin
          amp_ctrl <= amp_ctrl + 2'b01; // Cộng 1 để xoay vòng qua 4 mức: 00 -> 01 -> 10 -> 11 -> 00
        end  
      end else if (btn_down_tick) begin
        if (~SW[4]) begin
          if (freq_val >= step_freq + MIN_FREQ) freq_val <= freq_val - step_freq;
        end
      end
    end
  end
  assign tuning_word = freq_val * TW_1HZ;
  //================Frequency Control===========================
  logic [3:0] d0, d1, d2, d3, d4;
  assign d0 = freq_val % 10;
  assign d1 = (freq_val / 10) % 10;
  assign d2 = (freq_val / 100) % 10;
  assign d3 = (freq_val / 1000) % 10;
  assign d4 = (freq_val / 10000) % 10;
  hex_decoder #(.COMMON_ANODE(1'b1)) h0 (.bin(d0), .hex(HEX0));
  hex_decoder #(.COMMON_ANODE(1'b1)) h1 (.bin(d1), .hex(HEX1));
  hex_decoder #(.COMMON_ANODE(1'b1)) h2 (.bin(d2), .hex(HEX2));
  hex_decoder #(.COMMON_ANODE(1'b1)) h3 (.bin(d3), .hex(HEX3));
  hex_decoder #(.COMMON_ANODE(1'b1)) h4 (.bin(d4), .hex(HEX4));
  hex_decoder #(.COMMON_ANODE(1'b1)) h5 (.bin({2'b00, step_idx}), .hex(HEX5));
  // =======================================================
  // 4. GIAO TIẾP CODEC WM8731 & DATAPATH DDS
  // =======================================================
  PLL_12_288MHZ pll_inst (
    .refclk   (CLOCK_50),
    .rst      (~rst_n),
    .outclk_0 (clk_12M),
    .locked   ()
  );
  assign AUD_XCK = clk_12M;
  always_ff @(posedge clk_12M or negedge rst_n) begin
    if (!rst_n) start_cfg <= 1'b0;
    else        start_cfg <= 1'b1;
  end
  codec_setup #(.I2C_DIV(16)) i2c_config (
    .clk       (clk_12M),
    .rst_n     (rst_n),
    .start_cfg (start_cfg),
    // Config debug
    .cfg_done  (LEDR[0]),
    .cfg_error (LEDR[1]),
    .cfg_busy  (LEDR[2]),
    .i2c_sda   (FPGA_I2C_SDAT),
    .i2c_scl   (FPGA_I2C_SCLK)
  );
  logic signed [23:0] dds_wave_out;
  generator_wave #(
    .PHASE_WIDTH(10),
    .DATA_WIDTH(24)
  ) dds_core (
    .i_clk         (clk_12M),
    .i_rst_n       (rst_n),
    .i_noise_en    (SW[9]),
    .i_noise_lvl   (SW[8]),   // optional
    .i_tuning_word (tuning_word),
    .i_amp_ctrl    (amp_ctrl),
    .i_wave_sel    (SW[7:5]),
    .o_wave_out    (dds_wave_out)
  );
  i2s_tx_24bit i2s_transmitter (
      .clk     (clk_12M),
      .rst_n   (rst_n),
      .wave_in (dds_wave_out),
      .bclk    (AUD_BCLK),
      .lrclk   (AUD_DACLRCK),
      .sdata   (AUD_DACDAT)
  );
endmodule