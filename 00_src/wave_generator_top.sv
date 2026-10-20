module DE10_Standard_golden_top (
  input  logic        CLOCK_50,
  input  logic [3:0]  KEY,
  input  logic [9:0]  SW,
  output logic [9:0]  LEDR,
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
  
  // Audio I2C
  inout  wire         FPGA_I2C_SDAT,
  output logic        FPGA_I2C_SCLK,
  
  // Audio I2S
  output logic        AUD_XCK,
  inout  wire         AUD_BCLK,
  inout  wire         AUD_DACLRCK,
  output logic        AUD_DACDAT,
  inout  wire         AUD_ADCLRCK,
  input  logic        AUD_ADCDAT
);
  logic rst_n;
  // 1. CHỐNG RUNG CÁC NÚT NHẤN
  logic btn_down_tick, btn_up_tick, btn_step_tick;
  // 2. KHAI BÁO CÁC THANH GHI THAM SỐ
  // Tần số âm thanh mẫu của WM8731 là 48kHz. 
  // Công thức Tuning Word: TW = (F_out * 2^32) / 48000
  // Ví dụ 1Hz tương đương TW = 89478
  localparam int TW_1HZ    = 89478;
  localparam int MAX_FREQ  = 20000; // 20 kHz
  localparam int MIN_FREQ  = 1;     // 1 Hz
  logic [1:0]  amp_ctrl;         // Điều khiển biên độ (00: 25% -> 11: 100%)
  logic [1:0]  step_idx;         // Trạng thái của bước nhảy
  logic [3:0]  d0, d1, d2, d3, d4;
  logic [15:0] freq_val;         // Giá trị tần số đang hiển thị (Hz)
  logic [31:0] tuning_word;      // Bước nhảy pha thực tế đưa vào DDS
  logic [31:0] step_freq;        // Bước nhảy tần số (1, 10, 100, 1000)
  
  assign rst_n = KEY[0];
  assign LEDR  = SW;
  button_debouncer db_down (.clk(CLOCK_50), .rst_n(rst_n), .btn_in(KEY[1]), .btn_tick(btn_down_tick));
  button_debouncer db_up   (.clk(CLOCK_50), .rst_n(rst_n), .btn_in(KEY[2]), .btn_tick(btn_up_tick));
  button_debouncer db_step (.clk(CLOCK_50), .rst_n(rst_n), .btn_in(KEY[3]), .btn_tick(btn_step_tick));

  // 3. LOGIC ĐIỀU KHIỂN & CHẶN BỘ ĐẾM (SATURATION)
  always_ff @(posedge CLOCK_50) begin
    if (!rst_n) begin
      freq_val   <= 1000;      // Mặc định 1kHz
      amp_ctrl   <= 2'b11;     // Mặc định 100%
      step_idx   <= 2'b00;
      step_freq  <= 1;
    end else begin
      // Đổi bước nhảy (KEY[3])
      if (btn_step_tick) begin
        step_idx <= step_idx + 1;
        case (step_idx + 1)
          2'b00: step_freq <= 1;
          2'b01: step_freq <= 10;
          2'b10: step_freq <= 100;
          2'b11: step_freq <= 1000;
        endcase
      end
      // Xử lý Tăng/Giảm (KEY[2], KEY[1])
      if (btn_up_tick) begin
        case (SW[5:4]) // Menu Select
          2'b00: if (freq_val + step_freq <= MAX_FREQ) freq_val <= freq_val + step_freq;  // Chặn tần số Max
          2'b01: if (amp_ctrl < 2'b11)                 amp_ctrl <= amp_ctrl + 1;          // Chặn biên độ Max
        endcase
      end else if (btn_down_tick) begin
        case (SW[5:4])
          2'b00: if (freq_val >= step_freq + MIN_FREQ) freq_val <= freq_val - step_freq;  // Chặn Underflow
          2'b01: if (amp_ctrl > 2'b00)                 amp_ctrl <= amp_ctrl - 1;          // Chặn biên độ Min
        endcase
      end
    end
  end
  // Tính toán Tuning Word từ freq_val (Bộ nhân phần cứng DSP Block)
  assign tuning_word = freq_val * TW_1HZ;
  // 4. KHỞI TẠO BỘ TẠO SÓNG (DDS CORE)
  logic signed [23:0] dds_wave_out;
  generator_wave #(
    .PHASE_WIDTH(10), 
    .DATA_WIDTH(24)
  ) core_inst (
    .i_clk         (CLOCK_50),  // CHÚ Ý: Đọc thêm phần 2 bên dưới
    .i_rst_n       (rst_n),
    .i_noise_en    (SW[9]),
    .i_noise_lvl   (SW[8]),
    .i_tuning_word (tuning_word),
    .i_amp_ctrl    (amp_ctrl),
    .i_wave_sel    (SW[7:6]),
    .o_wave_out    (dds_wave_out)
  );

  // 5. HIỂN THỊ LÊN LED 7 ĐOẠN (Giả lập BCD cơ bản cho tần số)
  // Thực tế bạn sẽ cần module Bin2BCD (Double Dabble), ở đây mình chia nhẩm để minh họa
  assign d0 = freq_val % 10;
  assign d1 = (freq_val / 10) % 10;
  assign d2 = (freq_val / 100) % 10;
  assign d3 = (freq_val / 1000) % 10;
  assign d4 = (freq_val / 10000) % 10;
  hex_decoder #(.COMMON_ANODE(1'b1)) hex_inst_0 (.bin(d0), .hex(HEX0));
  hex_decoder #(.COMMON_ANODE(1'b1)) hex_inst_1 (.bin(d0), .hex(HEX1));
  hex_decoder #(.COMMON_ANODE(1'b1)) hex_inst_2 (.bin(d0), .hex(HEX2));
  hex_decoder #(.COMMON_ANODE(1'b1)) hex_inst_3 (.bin(d0), .hex(HEX3));
  hex_decoder #(.COMMON_ANODE(1'b1)) hex_inst_4 (.bin(d0), .hex(HEX4));
  // HEX5 dùng để hiển thị bước nhảy hiện tại (1, 2, 3, 4 tương ứng 1, 10, 100, 1k)
  hex_decoder #(.COMMON_ANODE(1'b1)) hex_inst_5 (.bin(d0), .hex(HEX5));

endmodule