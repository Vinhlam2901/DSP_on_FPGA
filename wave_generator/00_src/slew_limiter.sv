module slew_limiter #(
  parameter int DATA_WIDTH = 24
)(
  input  logic                         i_clk,
  input  logic                         i_rst_n,
  input  logic                         i_tick,     // 1 xung mỗi mẫu (48 kHz)
  input  logic                         i_en,       // 1: bật slew, 0: bám thẳng target
  input  logic        [30:0]           i_step,     // Độ thay đổi tối đa, LSB mỗi mẫu
  input  logic signed [DATA_WIDTH-1:0] i_target,
  output logic signed [DATA_WIDTH-1:0] o_val
);
  localparam int W = DATA_WIDTH + 1;   // 1 bit dự phòng để target - o_val không tràn

  logic signed [W-1:0] diff;
  logic signed [31:0]  step;

  assign diff = $signed({i_target[DATA_WIDTH-1], i_target})
              - $signed({o_val[DATA_WIDTH-1],    o_val});
  assign step = $signed({1'b0, i_step});

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      o_val <= '0;
    end else if (i_tick) begin
      if (!i_en)
        o_val <= i_target;
      else if (diff > step)
        o_val <= o_val + step[DATA_WIDTH-1:0];
      else if (diff < -step)
        o_val <= o_val - step[DATA_WIDTH-1:0];
      else
        o_val <= i_target;
    end
  end
endmodule