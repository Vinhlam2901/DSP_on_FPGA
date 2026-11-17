// IIR baseline: cascade of Direct Form I biquads, with a0 = 1.
// Each biquad follows v = b0*u + b1*x1 + b2*x2 - a1*y1 - a2*y2.
module iir_baseline #(
  parameter integer N_SECTIONS  = 3,
  parameter integer W_IN        = 24,
  parameter integer W_OUT       = 24,
  parameter integer W_COEF      = 18,
  parameter integer F_COEF      = 16,
  parameter integer INPUT_SHIFT = 2,
  parameter integer W_STATE     = W_IN + INPUT_SHIFT,
  parameter integer W_ACC       = W_STATE + W_COEF + 3,
  // Low to high: s0 b0,b1,b2,a1,a2; s1 b0,... . a0 is normalized to 1.
  parameter logic [N_SECTIONS*5*W_COEF-1:0] COEFFS = '0
)(
  input  logic                    clk,
  input  logic                    rst_n, // asynchronous assertion; release synchronously to clk
  input  logic                    in_valid,
  input  logic signed [W_IN-1:0]  x,
  output logic                    in_ready,
  output logic                    out_valid,
  output logic signed [W_OUT-1:0] y
);

  // 1. Mỗi section giữ hai input cũ và hai output cũ.
  logic signed [W_STATE-1:0] x1    [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] x2    [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] y1    [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] y2    [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] stage [0:N_SECTIONS];

  // Mở rộng signed lên W_STATE TRƯỚC khi dịch để không mất bit.
  logic signed [W_STATE-1:0] x_extended;
  assign x_extended = x;
  assign stage[0] = x_extended <<< INPUT_SHIFT;

  // 2. Mỗi section là một bản sao của khối biquad.
  for (genvar s = 0; s < N_SECTIONS; s = s + 1) begin : biquad
    logic signed [W_COEF-1:0] b0, b1, b2, a1, a2;
    assign b0 = COEFFS[(s*5+0)*W_COEF +: W_COEF];
    assign b1 = COEFFS[(s*5+1)*W_COEF +: W_COEF];
    assign b2 = COEFFS[(s*5+2)*W_COEF +: W_COEF];
    assign a1 = COEFFS[(s*5+3)*W_COEF +: W_COEF];
    assign a2 = COEFFS[(s*5+4)*W_COEF +: W_COEF];

    // Năm bộ nhân song song, các tích dùng độ rộng accumulator.
    logic signed [W_ACC-1:0] b0_u, b1_x1, b2_x2, a1_y1, a2_y2, sum;
    assign b0_u  = b0 * stage[s];
    assign b1_x1 = b1 * x1[s];
    assign b2_x2 = b2 * x2[s];
    assign a1_y1 = a1 * y1[s];
    assign a2_y2 = a2 * y2[s];

    assign sum = b0_u + b1_x1 + b2_x2 - a1_y1 - a2_y2;
    assign stage[s+1] = finish_section(sum);
  end

  // 3. Chỉ cập nhật thanh ghi z^-1 / z^-2 khi nhận mẫu mới.
  assign in_ready = rst_n;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (integer s = 0; s < N_SECTIONS; s = s + 1) begin
        x1[s] <= '0;
        x2[s] <= '0;
        y1[s] <= '0;
        y2[s] <= '0;
      end
      y <= '0;
      out_valid <= 1'b0;
    end else begin
      out_valid <= in_valid && in_ready;
      if (in_valid && in_ready) begin
        for (integer s = 0; s < N_SECTIONS; s = s + 1) begin
          x1[s] <= stage[s];
          x2[s] <= x1[s];
          y1[s] <= stage[s+1];
          y2[s] <= y1[s];
        end
        y <= finish_sample(stage[N_SECTIONS]);
      end
    end
  end

  // Fixed-point conversion only. The filter equations are above this block.
  localparam logic signed [W_ACC:0] ONE = 1;
  localparam logic signed [W_ACC:0] NEGATIVE_BIAS = (ONE <<< F_COEF) - 1;
  localparam logic signed [W_ACC:0] MAX_STATE = (ONE <<< (W_STATE - 1)) - 1;
  localparam logic signed [W_ACC:0] MIN_STATE = -(ONE <<< (W_STATE - 1));
  localparam logic signed [W_ACC:0] MAX_OUT = (ONE <<< (W_OUT - 1)) - 1;
  localparam logic signed [W_ACC:0] MIN_OUT = -(ONE <<< (W_OUT - 1));
  localparam logic signed [W_ACC:0] OUTPUT_BIAS =
      (INPUT_SHIFT == 0) ? 0 : (ONE <<< (INPUT_SHIFT - 1));

  // v[n] = saturate(sum / 2^F_COEF), rounding toward zero.
  // For a negative sum, adding 2^F_COEF-1 before >>> implements this rounding.
  function automatic logic signed [W_STATE-1:0] finish_section(
      input logic signed [W_ACC-1:0] sum);
    logic signed [W_ACC:0] scaled;
    begin
      scaled = sum;
      if (scaled < 0) scaled = scaled + NEGATIVE_BIAS;
      scaled = scaled >>> F_COEF;
      if      (scaled > MAX_STATE) finish_section = MAX_STATE;
      else if (scaled < MIN_STATE) finish_section = MIN_STATE;
      else                         finish_section = scaled;
    end
  endfunction

  // Undo the input scaling, then round and saturate to the DAC width.
  function automatic logic signed [W_OUT-1:0] finish_sample(
      input logic signed [W_STATE-1:0] value);
    logic signed [W_ACC:0] scaled;
    begin
      scaled = value;
      scaled = (scaled + OUTPUT_BIAS) >>> INPUT_SHIFT;
      if      (scaled > MAX_OUT) finish_sample = MAX_OUT;
      else if (scaled < MIN_OUT) finish_sample = MIN_OUT;
      else                       finish_sample = scaled;
    end
  endfunction
endmodule
