module DE10_Standard_golden_top #(
  parameter int PHASE_WIDTH = 10,  // Số bit biểu diễn góc pha (2^10 = 1024 mẫu góc)
  parameter int DATA_WIDTH  = 24
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
//==============DECLARATION==================================
  localparam logic [15:0]       MAX_FREQ = 16'd20000;
  localparam logic [15:0]       MIN_FREQ = 16'd1;
  localparam logic [15:0]       DEF_FREQ = 16'd1000;
  localparam logic [8:0]        TW_1HZ   = 9'd350;
  localparam int                PW_BUS = 16 + 2 + 3 + 1 + 2;
  localparam int                SW_WAIT_CYCLES = 500_000;
  localparam logic [PW_BUS-1:0] CFG_DEFAULT = {DEF_FREQ, 2'b11, 3'b000, 1'b0, 2'b01};
  logic [PW_BUS-1:0] par_src, cfg_hold, par_12;
  logic              cfg_req, cfg_ack, cfg_sent;
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
  logic [1:0]        req_sync, ack_sync, cfg50_reset_sr;
  logic              cfg50_n;
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
  logic [5:0]        sw_meta, sw_sync;
  logic [5:0]        sw_candidate, sw_stable;
  logic [18:0]       sw_count;
  logic              clk_12M, pll_locked;
  logic              rst50_n;
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
  logic [1:0]        rst50_sr;
  logic              rst12_src_n;
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
  logic [1:0]        rst12_sr;
  logic              rst12_n;
  logic              btn_down_tick, btn_up_tick, btn_step_tick;
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
  logic [1:0]        mode_sr;
  logic              mode_amp;
  logic [15:0]       freq_val;
  logic [15:0]       step_freq;
  logic [1:0]        step_idx;
  logic [1:0]        amp_ctrl;           // 00: 25%, 01: 50%, 10: 75%, 11: 100%
  logic [3:0]        d0, d1, d2, d3, d4, d5;
  logic [15:0]       q0, q1, q2, q3, q4;
  logic [15:0]       freq_12;
  logic [1:0]        amp_12;
  logic [2:0]        wsel_12;
  logic              noise_12;
  logic [1:0]        duty_12;
  logic [16:0]       cfg_wait;
  logic              start_cfg;
  logic signed [DATA_WIDTH-1:0] dds_wave_out;

  // =======================================================
  // 1. PLL & RESET
  // =======================================================
  PLL_12_288MHZ pll_inst (
    .refclk   (CLOCK_50),
    .rst      (1'b0),          // [Sửa] Gốc: ~rst_n. KEY0 không reset PLL, MCLK cho codec luôn chạy
    .outclk_0 (clk_12M),
    .locked   (pll_locked)     // [Sửa] Gốc: bỏ trống
  );
  assign AUD_XCK   = clk_12M;
  assign LEDR[3]   = pll_locked;   // [Thêm] Báo PLL đã locked (gốc: LEDR3 không dùng)
  assign LEDR[9:4] = SW[9:4];
  //------------50Mhz Reset------------------------------
  always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
    if (!KEY[0]) begin
      rst50_sr <= 2'b00;
    end else begin
      rst50_sr <= {rst50_sr[0], 1'b1};
    end
  end
  assign rst50_n = rst50_sr[1];
  //------------12Mhz Reset------------------------------
  // Chỉ thoát reset khi đã thả KEY0 và PLL đã locked
  assign rst12_src_n = KEY[0] & pll_locked;
  always_ff @(posedge clk_12M or negedge rst12_src_n) begin
    if (!rst12_src_n) begin
      rst12_sr <= 2'b00;
    end else begin
      rst12_sr <= {rst12_sr[0], 1'b1};
    end
  end
  assign rst12_n = rst12_sr[1];
  //==============BUTTON DEBOUNCE==============================
  button_debouncer db_down (.clk(CLOCK_50), .rst_n(rst50_n), .btn_in(KEY[1]), .btn_tick(btn_down_tick));
  button_debouncer db_up   (.clk(CLOCK_50), .rst_n(rst50_n), .btn_in(KEY[2]), .btn_tick(btn_up_tick));
  button_debouncer db_step (.clk(CLOCK_50), .rst_n(rst50_n), .btn_in(KEY[3]), .btn_tick(btn_step_tick));
  // [Thêm] Đồng bộ SW4 vào miền 50MHz: SW4 = 0 chỉnh biên độ, SW4 = 1 chỉnh tần số
  always_ff @(posedge CLOCK_50 or negedge rst50_n) begin
    if (!rst50_n) mode_sr <= '0;
    else mode_sr <= {mode_sr[0], SW[4]};
  end
  assign mode_amp = ~mode_sr[1];
  // [Sửa] Bước nhảy tần số tính tổ hợp theo step_idx (gốc: thanh ghi step_freq cập nhật khi nhấn KEY3)
  always_comb begin
    case (step_idx)
      2'd0:    step_freq = 16'd1;
      2'd1:    step_freq = 16'd10;
      2'd2:    step_freq = 16'd100;
      default: step_freq = 16'd1000;
    endcase
  end
  //================Amplitude & Frequency Control===========================
  // [Sửa] Gốc: KEY1 luôn giảm tần số (cả khi SW4 = 0), SW4 = 1 thì KEY1 không làm gì,
  //       biên độ chỉ tăng xoay vòng. Nay KEY2 tăng / KEY1 giảm theo chế độ SW4,
  //       biên độ và tần số đều chặn ở giá trị min/max, bỏ qua khi nhấn 2 nút cùng lúc
  always_ff @(posedge CLOCK_50) begin
    if (!rst50_n) begin
      freq_val <= DEF_FREQ;
      amp_ctrl <= 2'b11;
      step_idx <= 2'd0;
    end else begin
      if (btn_step_tick)
        step_idx <= step_idx + 2'd1;
      if (btn_up_tick && !btn_down_tick) begin
        if (!mode_amp) begin
          // Tăng tần số, chặn tại MAX_FREQ
          if (freq_val <= MAX_FREQ - step_freq) begin
            freq_val <= freq_val + step_freq;
          end else begin
            freq_val <= MAX_FREQ;
          end
        end else begin
          if (amp_ctrl != 2'b11) begin
            amp_ctrl <= amp_ctrl + 2'b01;   // Tối đa 100%
          end
        end
      end else if (btn_down_tick && !btn_up_tick) begin
        if (!mode_amp) begin
          // Giảm tần số, chặn tại MIN_FREQ
          if (freq_val >= MIN_FREQ + step_freq) begin
            freq_val <= freq_val - step_freq;
          end else begin
            freq_val <= MIN_FREQ;
          end
        end else begin
          if (amp_ctrl != 2'b00) begin
            amp_ctrl <= amp_ctrl - 2'b01;   // Tối thiểu 25%
          end
        end
      end
    end
  end

  //================7 SEGMENT DISPLAY===========================
  // HEX4..0: tần số, HEX5: bước tần số (SW4 = 1) hoặc mức biên độ 1..4 (SW4 = 0)
  // [Sửa] Phép chia/mod khai báo đủ bit; HEX5 hiện thêm mức biên độ khi SW4 = 0
  assign q0 =  freq_val % 16'd10;
  assign q1 = (freq_val / 16'd10)    % 16'd10;
  assign q2 = (freq_val / 16'd100)   % 16'd10;
  assign q3 = (freq_val / 16'd1000)  % 16'd10;
  assign q4 = (freq_val / 16'd10000) % 16'd10;
  assign {d0, d1, d2, d3, d4} = {q0[3:0], q1[3:0], q2[3:0], q3[3:0], q4[3:0]};
  assign d5 = mode_amp ? {2'b00, amp_ctrl} + 4'd1 : {2'b00, step_idx};
  hex_decoder #(.COMMON_ANODE(1'b1)) h0 (.bin(d0), .hex(HEX0));
  hex_decoder #(.COMMON_ANODE(1'b1)) h1 (.bin(d1), .hex(HEX1));
  hex_decoder #(.COMMON_ANODE(1'b1)) h2 (.bin(d2), .hex(HEX2));
  hex_decoder #(.COMMON_ANODE(1'b1)) h3 (.bin(d3), .hex(HEX3));
  hex_decoder #(.COMMON_ANODE(1'b1)) h4 (.bin(d4), .hex(HEX4));
  hex_decoder #(.COMMON_ANODE(1'b1)) h5 (.bin(d5), .hex(HEX5));
  // =======================================================
  // CODEC WM8731 & DATAPATH DDS
  // =======================================================
  // Synchronize physical switches; accept a vector after 10 ms stable.
  // SW[7:5]: waveform, SW[8]: noise, SW[1:0]: duty (01 = 50%).
  always_ff @(posedge CLOCK_50 or negedge rst50_n) begin
    if (!rst50_n) begin
      sw_meta <= 6'b000001;
      sw_sync <= 6'b000001;
    end else begin
      sw_meta <= {SW[7:5], SW[8], SW[1:0]};
      sw_sync <= sw_meta;
    end
  end
  always_ff @(posedge CLOCK_50 or negedge rst50_n) begin
    if (!rst50_n) begin
      sw_candidate <= 6'b000001;
      sw_stable <= 6'b000001;
      sw_count <= '0;
    end else if (sw_sync != sw_candidate) begin
      sw_candidate <= sw_sync;
      sw_count <= '0;
    end else if (sw_count == SW_WAIT_CYCLES-1) begin
      sw_stable <= sw_candidate;
    end else begin
      sw_count <= sw_count + 1'b1;
    end
  end
  // Both handshake endpoints share asynchronous assertion on KEY0/lock loss,
  // but release reset in their own clock domain. User settings survive lock loss.
  always_ff @(posedge CLOCK_50 or negedge rst12_src_n) begin
    if (!rst12_src_n) begin
      cfg50_reset_sr <= '0;
    end else begin 
      cfg50_reset_sr <= {cfg50_reset_sr[0], 1'b1};
    end
  end
  assign cfg50_n = cfg50_reset_sr[1];
  assign par_src = {freq_val, amp_ctrl, sw_stable};
  always_ff @(posedge CLOCK_50 or negedge cfg50_n) begin
    if (!cfg50_n) begin
      ack_sync <= '0;
    end else begin
      ack_sync <= {ack_sync[0], cfg_ack};
    end
  end
  always_ff @(posedge CLOCK_50 or negedge cfg50_n) begin
    if (!cfg50_n) begin
      cfg_hold <= CFG_DEFAULT;
      cfg_req <= 1'b0;
      cfg_sent <= 1'b0;
    end else if (rst50_n && (cfg_req == ack_sync[1]) &&
                (!cfg_sent || par_src != cfg_hold)) begin
      cfg_hold <= par_src;
      cfg_req <= ~cfg_req;
      cfg_sent <= 1'b1;
    end
  end
  always_ff @(posedge clk_12M or negedge rst12_n) begin
    if (!rst12_n) begin
      req_sync <= '0;
    end else begin
      req_sync <= {req_sync[0], cfg_req};
    end
  end
  // Bundled data: cfg_hold remains unchanged until ACK returns.
  // wg.sdc bounds its delay to less than one destination clock period.
  always_ff @(posedge clk_12M or negedge rst12_n) begin
    if (!rst12_n) begin
      cfg_ack <= 1'b0;
      par_12 <= CFG_DEFAULT;
    end else if (req_sync[1] != cfg_ack) begin
      par_12 <= cfg_hold;
      cfg_ack <= req_sync[1];
    end
  end
  assign {freq_12, amp_12, wsel_12, noise_12, duty_12} = par_12;
  // Tính tuning word từ giá trị ĐÃ ĐỒNG BỘ
  logic [31:0] tuning_word;
  always_ff @(posedge clk_12M or negedge rst12_n) begin
    if (!rst12_n) begin
      tuning_word <= '0;
    end else begin
      tuning_word <= freq_12 * TW_1HZ;
    end
  end
  //================CODEC CONFIGURATION===========================
  // [Sửa] Gốc: bắt đầu cấu hình ngay 1 clock sau reset. Nay chờ ~5.3ms sau khi thoát reset
  always_ff @(posedge clk_12M or negedge rst12_n) begin
    if (!rst12_n) begin
      cfg_wait  <= '0;
      start_cfg <= 1'b0;
    end else if (!cfg_wait[16]) begin
      cfg_wait  <= cfg_wait + 17'd1;
    end else begin
      start_cfg <= 1'b1;
    end
  end
  codec_setup #(
    .I2C_DIV(16)
  ) i2c_config (
    .clk       (clk_12M),
    .rst_n     (rst12_n),
    .start_cfg (start_cfg),
    // Config debug
    .cfg_done  (LEDR[0]),
    .cfg_error (LEDR[1]),
    .cfg_busy  (LEDR[2]),
    .i2c_sda   (FPGA_I2C_SDAT),
    .i2c_scl   (FPGA_I2C_SCLK)
  );
  //================DDS & I2S===========================
  // [Sửa] Reset dùng rst12_n; noise_en, amp, wave_sel lấy từ bản đã đồng bộ (gốc: SW và amp_ctrl đi thẳng)
  generator_wave #(
    .PHASE_WIDTH (PHASE_WIDTH),
    .DATA_WIDTH  (DATA_WIDTH)
  ) dds_core (
    .i_clk         (clk_12M),
    .i_rst_n       (rst12_n),
    .i_noise_en    (noise_12),     // gốc: SW[8]
    .i_tuning_word (tuning_word),
    .i_amp_ctrl    (amp_12),       // gốc: amp_ctrl
    .i_duty_ctrl   (duty_12),
    .i_wave_sel    (wsel_12),      // gốc: SW[7:5]
    .o_wave_out    (dds_wave_out)
  );
  i2s_tx_24bit i2s_transmitter (
    .clk     (clk_12M),
    .rst_n   (rst12_n),
    .wave_in (dds_wave_out),
    .bclk    (AUD_BCLK),
    .lrclk   (AUD_DACLRCK),
    .sdata   (AUD_DACDAT)
  );
endmodule
