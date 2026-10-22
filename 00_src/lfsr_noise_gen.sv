module lfsr_noise_gen #(
  parameter logic [31:0] SEED      = 32'hACE1_2B5F, // khác 0
  parameter int          OUT_WIDTH = 24
)(
  input  logic                 i_clk,
  input  logic                 i_rst_n,
  input  logic                 i_en,
  output logic [OUT_WIDTH-1:0] o_noise_out
);
  logic [31:0] lfsr_reg;
  logic        feedback;

  // Đa thức tối đa 32 bit: x^32 + x^22 + x^2 + x + 1
  // Chu kỳ 2^32 - 1 (~6 phút khi lấy mẫu mỗi 256 clock ở 48 kHz)
  assign feedback = lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1] ^ lfsr_reg[0];

  always_ff @(posedge i_clk) begin
    if (!i_rst_n)  lfsr_reg <= SEED;
    else if (i_en) lfsr_reg <= {lfsr_reg[30:0], feedback};
  end

  assign o_noise_out = lfsr_reg[31 -: OUT_WIDTH];
endmodule