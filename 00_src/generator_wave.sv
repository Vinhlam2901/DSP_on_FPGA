module generator_wave #(
  parameter int PHASE_WIDTH = 10,  // Số bit biểu diễn góc pha (2^8 = 256 mẫu góc)
  parameter int DATA_WIDTH = 24
)(
  input  logic                         i_clk,
  input  logic                         i_rst_n,
  input  logic                         i_noise_en,
  input  logic                         i_noise_lvl,
  input  logic [31:0]                  i_tuning_word,  // Điều khiển Tần số chung
  input  logic [1:0]                   i_amp_ctrl,  // Điều khiển Biên độ chung (00: 25%, 01: 50%, 10: 75%, 11: 100%)
  input  logic [1:0]                   i_wave_sel,     // 00: Sine, 01: Triangle, 10: Sawtooth, 11: ECG
  output logic signed [DATA_WIDTH-1:0] o_wave_out
);

//=============DECLARATION=======================================
  localparam int NUM_SAMPLES = 1 << PHASE_WIDTH;
  localparam real PI = 3.141592653589793;
    
  logic        [31:0]           phase_acc;
  logic        [31:0]           phase_acc_prev;
  logic        [7:0]            tri_unsigned;
  // 2. ROM cho Sóng Sine và ECG
  logic signed [DATA_WIDTH-1:0] sine_lut [NUM_SAMPLES];
  logic signed [DATA_WIDTH-1:0] ecg_lut [NUM_SAMPLES]; 
  // 3. Khối tạo Tín hiệu gốc (Raw Signals)
  logic signed [DATA_WIDTH-1:0] raw_sine;
  logic signed [DATA_WIDTH-1:0] raw_triangle;
  logic signed [DATA_WIDTH-1:0] raw_sawtooth;
  logic signed [DATA_WIDTH-1:0] raw_ecg;
  logic signed [DATA_WIDTH-1:0] raw_square;
  logic signed [DATA_WIDTH-1:0] selected_wave;
  logic signed [DATA_WIDTH-1:0] wave_amp_controlled;
  logic        [15:0]           noise_out;      // Ngõ ra từ module lfsr_noise_gen
  logic signed [15:0]           noise_signed;   // Nhiễu sau khi đã chuyển thành số có dấu
  logic signed [DATA_WIDTH-1:0] noise_scaled;   // Nhiễu đã được mở rộng lên 24-bit
  logic signed [DATA_WIDTH-1:0] final_out;      // Sóng mang ra DAC
//=================ROM====================================
  initial begin
    real angle;
    real sin_val;
    int max_amplitude;
    max_amplitude = (1 << (DATA_WIDTH - 1)) - 1; // Giá trị cực đại của số nguyên có dấu
    for (int i = 0; i < NUM_SAMPLES; i++) begin
      angle = (2.0 * PI * i) / real'(NUM_SAMPLES);
      sin_val = $sin(angle);
      // Ép kiểu về số nguyên có dấu và lưu vào ROM
      sine_lut[i] = signed'(int'(sin_val * real'(max_amplitude)));
    end
  end
  $readmemh("ecg_real_1024_24bit.mem", ecg_lut);

  // Lấy dữ liệu ROM cho Sine và ECG
  assign raw_sine   = sine_lut[phase_acc[31 -: PHASE_WIDTH]];
  assign raw_ecg    = ecg_lut[phase_acc[31 -: PHASE_WIDTH]];
  assign raw_square = (!phase_acc[31]) ? 8'd127 : -8'd128;
//==================INSTANTIATION============================
  cla_adder_24bit noise_adder (
    .a_i      (wave_ext),
    .b_i      (noise_scaled),
    .cin_i    (1'b0),
    .cout_o   (),
    .result_o(final_out)
  );
  cla_adder_32bit phase_accum (
    .a_i      (phase_acc),
    .b_i      (i_tuning_word),
    .cin_i    (1'b0),
    .cout_o   (),
    .result_o(phase_acc_prev)
  );
  lfsr_noise_gen #(
    .SEED(16'hABCD)
  ) noise_gen (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_en(i_noise_en),
    .o_noise_out(noise_out)
  );
//=============PLL==========================================
    always_ff @(posedge i_clk) begin
      if (!i_rst_n) begin
        phase_acc <= '0;
      end else begin
        phase_acc <= phase_acc_prev; 
      end
    end
  // Thuật toán tạo sóng Răng cưa (Đảo bit cao nhất để chuyển từ Unsigned sang Signed)
  assign raw_sawtooth = {~phase_acc[31], phase_acc[30:24]};
  // Thuật toán tạo sóng Tam giác bằng cách "gấp" pha
  // Lấy 8 bit từ [30:23] để biên độ chạy đủ full-scale, đảo lại nếu nửa chu kỳ sau
  assign tri_unsigned = phase_acc[31] ? ~phase_acc[30:23] : phase_acc[30:23];
  assign raw_triangle = tri_unsigned - 8'd128; // Dời trục tọa độ để thành số có dấu
  // 4. Khối Multiplexer chọn sóng
  always_comb begin
    case (i_wave_sel)
      2'b00: selected_wave = raw_sine;
      2'b01: selected_wave = raw_triangle;
      2'b10: selected_wave = raw_sawtooth;
      2'b11: selected_wave = raw_ecg;
    endcase
  end
  // 5. Khối điều chỉnh Biên độ (Dùng chung cho tất cả)
  always_comb begin
    case (i_amp_ctrl)
      2'b00: wave_amp_controlled = selected_wave >>> 2;                      // 25%
      2'b01: wave_amp_controlled = selected_wave >>> 1;                      // 50%
      2'b10: wave_amp_controlled = (selected_wave >>> 1) + (selected_wave >>> 2); // 75%
      2'b11: wave_amp_controlled = selected_wave;                            // 100%
    endcase
  end
  assign noise_signed = {~noise_out[15], noise_out[14:0]};
  // 3. Mở rộng lên 24-bit và chỉnh mức độ nhiễu (Amplitude Scaling)
  // Giả sử có một switch SW để chọn mức nhiễu:
  // - 1'b0: Nhiễu nhỏ (Dịch nhiễu xuống các bit thấp, giữ lại dấu)
  // - 1'b1: Nhiễu lớn (Đẩy nhiễu lên các bit cao hơn)
  always_comb begin
    if (i_noise_lvl == 1'b0) begin
      // Kéo giãn dấu (Sign-extension) 8 bit cao, đặt nhiễu ở 16 bit thấp
      noise_scaled = {{8{noise_signed[15]}}, noise_signed}; 
    end else begin
      // Đặt nhiễu lên cao hơn một chút, chèn 4 số 0 vào LSB
      noise_scaled = {{4{noise_signed[15]}}, noise_signed, 4'b0000}; 
    end
  end
  // 4. Kết hợp sóng gốc và nhiễu
  assign o_wave_out = i_noise_en ? final_out : wave_amp_controlled;
endmodule