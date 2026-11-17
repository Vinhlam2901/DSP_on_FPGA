module generator_wave #(
  parameter int PHASE_WIDTH = 10,  // Số bit biểu diễn góc pha (2^10 = 1024 mẫu góc)
  parameter int DATA_WIDTH = 24
)(
  input  logic                         i_clk,
  input  logic                         i_rst_n,
  input  logic                         i_noise_en,
  input  logic [31:0]                  i_tuning_word,   // Điều khiển Tần số chung
  input  logic [1:0]                   i_amp_ctrl,      // Điều khiển Biên độ chung (00: 25%, 01: 50%, 10: 75%, 11: 100%)
  input  logic [2:0]                   i_wave_sel,   // 00: Sine, 01: Triangle, 10: Sawtooth, 11: ECG
  input  logic [1:0]                   i_duty_ctrl,  // test duty cycle 
  output logic signed [DATA_WIDTH-1:0] o_wave_out
);
//=============DECLARATION=======================================
  localparam int NUM_SAMPLES = 1 << PHASE_WIDTH;
  localparam int NOISE_SHIFT = 2;   // mức nhiễu tương đối so với sóng
  localparam real PI = 3.141592653589793;
  // Cực đại dương 24-bit: 0111...111 = 24'h7FFFFF
  localparam signed [DATA_WIDTH-1:0] MAX_POS = (1 << (DATA_WIDTH - 1)) - 1; 
  // Cực đại âm 24-bit:   1000...000 = 24'h800000
  localparam signed [DATA_WIDTH-1:0] MAX_NEG = ~(MAX_POS);
  logic                         ovf;
  logic        [31:0]           phase_acc;
  logic        [31:0]           phase_acc_prev;
  logic [DATA_WIDTH-1:0] tri_unsigned;
  logic [31:0] tri_peak_phase;
  logic [31:0] tri_phase_delta;
  logic [63:0] tri_scaled;
  logic signed [DATA_WIDTH-1:0] sine_lut [NUM_SAMPLES];
  logic signed [DATA_WIDTH-1:0] ecg_lut [NUM_SAMPLES]; 
  logic signed [DATA_WIDTH-1:0] raw_sine;
  logic signed [DATA_WIDTH-1:0] raw_triangle;
  logic signed [DATA_WIDTH-1:0] raw_sawtooth;
  logic signed [DATA_WIDTH-1:0] raw_ecg;
  logic signed [DATA_WIDTH-1:0] raw_square;
  logic signed [DATA_WIDTH-1:0] selected_wave;
  logic signed [DATA_WIDTH-1:0] wave_amp_controlled;
  logic        [DATA_WIDTH-1:0] noise_out;      // Ngõ ra từ module lfsr_noise_gen
  logic signed [DATA_WIDTH-1:0] noise_signed;   // Nhiễu sau khi đã chuyển thành số có dấu
  logic signed [DATA_WIDTH-1:0] noise_scaled;   // Nhiễu đã được mở rộng lên 24-bit
  logic signed [DATA_WIDTH-1:0] final_out;      // Sóng mang ra DAC
  	// Hàm điều chỉnh biên độ dùng chung cho cả sóng và nhiễu
	function automatic logic signed [DATA_WIDTH-1:0] amp_scale(
	  input logic signed [DATA_WIDTH-1:0] x,
	  input logic        [1:0]            sel
	);
	  case (sel)
		 2'b00: amp_scale = x >>> 2;                  // 25%
		 2'b01: amp_scale = x >>> 1;                  // 50%
		 2'b10: amp_scale = (x >>> 1) + (x >>> 2);    // 75%
		 2'b11: amp_scale = x;                        // 100%
	  endcase
	endfunction
//=================ROM====================================
  initial begin
	 $readmemh("../00_src/sine_real_1024_24bit.mem", sine_lut);
	 $readmemh("../00_src/ecg_real_1024_24bit.mem", ecg_lut);
  end
  // Lấy dữ liệu ROM cho Sine và ECG
  assign raw_sine     = sine_lut[phase_acc[31 -: PHASE_WIDTH]];
  assign raw_ecg      = ecg_lut[phase_acc[31 -: PHASE_WIDTH]];
  always_comb begin                                              // assign square ...
    case (i_duty_ctrl)
      2'b00: raw_square = (phase_acc[31:30] == 2'b00) ? MAX_POS : MAX_NEG;     // 25%
      2'b01: raw_square = (phase_acc[31]    == 1'b0)  ? MAX_POS : MAX_NEG;     // 50%
      2'b10: raw_square = (phase_acc[31:30] != 2'b11) ? MAX_POS : MAX_NEG;     // 75%
      2'b11: raw_square = (phase_acc < 32'hFD70_A3D7) ? MAX_POS : MAX_NEG;     // xấp xỉ 99%
    default: raw_square = (phase_acc[31]    == 1'b0)  ? MAX_POS : MAX_NEG;
    endcase
  end
  // Sawtooth chuẩn: tang tu am cuc dai den duong cuc dai 
  assign raw_sawtooth = $signed(phase_acc[31 -: DATA_WIDTH] ^ {1'b1, {(DATA_WIDTH-1){1'b0}}});
  // Phase bits interpreted as two's-complement produce a full-scale sawtooth.
  // Fold the phase at half-cycle to form a 0 -> peak -> 0 triangle.
  // Taking [30:7] scales the 31-bit folded phase to the full DATA_WIDTH range.
  localparam logic [31:0] TRI_PEAK_25  = 32'h4000_0000;
  localparam logic [31:0] TRI_PEAK_50  = 32'h8000_0000;
  localparam logic [31:0] TRI_PEAK_75  = 32'hC000_0000;
  localparam logic [31:0] TRI_PEAK_100 = 32'hFFFF_FF00;
  always_comb begin
    // Mac dinh
    tri_peak_phase = TRI_PEAK_25;
    tri_phase_delta = 32'd0;
    tri_scaled = 64'd0;
    tri_unsigned = '0;
    raw_triangle = '0;
    // Chon vi tri dinh theo duty_ctrl
    case (i_duty_ctrl)
        2'b00:   tri_peak_phase = TRI_PEAK_25;
        2'b01:   tri_peak_phase = TRI_PEAK_50;
        2'b10:   tri_peak_phase = TRI_PEAK_75;
        2'b11:   tri_peak_phase = TRI_PEAK_100;
        default: tri_peak_phase = TRI_PEAK_25;
    endcase
    if (phase_acc < tri_peak_phase) begin
      // Nhanh tang: MAX_NEG -> MAX_POS
      tri_scaled   = ({32'd0, phase_acc} * ((64'd1 << DATA_WIDTH) - 64'd1)) / {32'd0, tri_peak_phase};
      tri_unsigned = tri_scaled[DATA_WIDTH-1:0];
    end else begin
      // Nhanh giam: MAX_POS -> MAX_NEG
      tri_phase_delta = phase_acc - tri_peak_phase;
      tri_scaled      = ({32'd0, tri_phase_delta} * ((64'd1 << DATA_WIDTH) - 64'd1)) / ((64'd1 << 32) - {32'd0, tri_peak_phase});
      tri_unsigned    = {DATA_WIDTH{1'b1}} - tri_scaled[DATA_WIDTH-1:0];
    end
    // Chuyen tu so khong dau sang so co dau
    raw_triangle = $signed(tri_unsigned ^ {1'b1, {(DATA_WIDTH-1){1'b0}}});
  end
//==================INSTANTIATION============================
  cla_adder_24bit noise_adder (
    .a_i      (wave_amp_controlled[23:0]),
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
 lfsr_noise_gen #(.OUT_WIDTH(DATA_WIDTH)) noise_gen (
    .i_clk       (i_clk),
    .i_rst_n     (i_rst_n),
    .i_en        (i_noise_en),
    .o_noise_out (noise_out)
  );
  // Bit ngẫu nhiên đều nên đọc thẳng như số có dấu là được,
  // không cần đảo MSB như bản cũ.
  assign noise_signed = $signed(noise_out);
  assign ovf = (wave_amp_controlled[23] == noise_scaled[23]) && (final_out[23] != wave_amp_controlled[23]);
  assign o_wave_out = !i_noise_en ? wave_amp_controlled :
                      ovf ? (wave_amp_controlled[23] ? MAX_NEG : MAX_POS) : final_out;
//=============PLL==========================================
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      phase_acc <= '0;
    end else begin
      phase_acc <= phase_acc_prev; 
    end
  end
  // 4. Khối Multiplexer chọn sóng
  always_comb begin
    case (i_wave_sel)
      3'b000:  selected_wave = raw_sine;     // Sóng Sine
      3'b001:  selected_wave = raw_square;   // Sóng Vuông
      3'b010:  selected_wave = raw_triangle; // Sóng Tam giác
      3'b011:  selected_wave = raw_sawtooth; // Sóng sawtooth
      3'b100:  selected_wave = raw_ecg;      // Sóng ECG
      default: selected_wave = raw_sine;
    endcase
  end
  // 5. Khối điều chỉnh Biên độ (Dùng chung cho tất cả)

	assign wave_amp_controlled = amp_scale(selected_wave, i_amp_ctrl);
	assign noise_scaled        = amp_scale(noise_signed, i_amp_ctrl) >>> NOISE_SHIFT;
	
endmodule