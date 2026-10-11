module lfsr_noise_gen #(
  parameter logic [15:0] SEED = 16'hACE1 // Initial value
)(
  input  logic        i_clk,
  input  logic        i_rst_n,
  input  logic        i_enable,
  output logic [15:0] o_noise_out
);

  logic [15:0] lfsr_reg;
  logic        feedback;
  // Đa thức phản hồi cho LFSR 16-bit đạt chu kỳ tối đa (Maximal Length Polynomial)
  // Đa thức: x^16 + x^14 + x^13 + x^11 + 1 (Tương ứng các bit 15, 13, 12, 10)
  assign feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];
  always_ff @(posedge i_clk) begin
    if (!i_rst_n) begin
      lfsr_reg <= SEED;
    end else if (i_enable) begin
      // Dịch toàn bộ mảng sang trái 1 bit, và nhét bit feedback vào vị trí LSB
      lfsr_reg <= {lfsr_reg[14:0], feedback}; 
    end
  end
  assign o_noise_out = lfsr_reg;
endmodule