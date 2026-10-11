module sine_generator #(
  parameter int PHASE_WIDTH = 10,  // Số bit biểu diễn góc pha (2^8 = 256 mẫu góc)
  parameter int DATA_WIDTH  = 8   // Độ phân giải biên độ (Dạng số nguyên có dấu 8-bit)
)(
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic        [1:0]             amp_control,  // 00: 25%, 01: 50%, 10: 75%, 11: 100%
  input  logic        [31:0] tuning_word,  // Bước nhảy pha (Quyết định tần số đầu ra)
  output logic signed [DATA_WIDTH-1:0]  sine_out
);

  localparam int NUM_SAMPLES = 1 << PHASE_WIDTH;
  localparam real PI = 3.141592653589793;
  // Khai báo bộ nhớ ROM chứa bảng mã Sin (Look-Up Table)
  logic signed [DATA_WIDTH-1:0] sine_lut [NUM_SAMPLES];
  // Bộ tích lũy pha (Phase Accumulator)
  logic        [31:0]           phase_acc;
  logic signed [DATA_WIDTH-1:0] raw_sine;

  // Tính toán trước các giá trị sóng Sin và nạp vào ROM tại thời điểm tổng hợp (Synthesis-time)
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
  // Khối mạch logic cập nhật pha liên tục theo xung Clock
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      phase_acc <= '0;
      raw_sine  <= '0;
    end else begin
      phase_acc <= phase_acc + tuning_word; 
      raw_sine  <= sine_lut[phase_acc[31 -: PHASE_WIDTH]];    
    end
  end
// Khối điều chỉnh biên độ bằng dịch bit (Shift)
  always_comb begin
    case (amp_control)
      2'b00:   sine_out = raw_sine >>> 2;                       // Giảm 4 lần (25%)
      2'b01:   sine_out = raw_sine >>> 1;                       // Giảm 2 lần (50%)
      2'b10:   sine_out = (raw_sine >>> 1) + (raw_sine >>> 2);  // 75% (1/2 + 1/4)
      2'b11:   sine_out = raw_sine;            
      default: sine_out = '0;                 // 100%
    endcase
  end
endmodule