// FIR folded: compute one term h[tap]*x_delay[tap] on each clock.
// One multiplier + one accumulator implement the same convolution as baseline.
module fir_folded #(
  parameter integer N_TAPS = 21,
  parameter integer W_IN = 24,
  parameter integer W_OUT = 24,
  parameter integer W_COEF = 18,
  parameter integer F_COEF = 17,
  parameter integer W_ACC = W_IN + W_COEF + $clog2(N_TAPS) + 1,
  // Tap zero occupies the least significant W_COEF bits. Default: muted.
  parameter logic [N_TAPS*W_COEF-1:0] COEFFS = '0
)(
  input logic clk,
  input logic rst_n, // asynchronous assertion; release synchronously to clk
  input logic in_valid,
  output logic in_ready,
  input logic signed [W_IN-1:0] x,
  output logic out_valid,
  output logic signed [W_OUT-1:0] y
);

  // 1. ROM hệ số: h[0], h[1], ..., h[N_TAPS-1].
  // Tách hệ số Python thành mảng h[] để viết công thức dễ đọc.
  wire signed [W_COEF-1:0] h [0:N_TAPS-1];
  for (genvar k = 0; k < N_TAPS; k = k + 1) begin : coefficients
    assign h[k] = COEFFS[k*W_COEF +: W_COEF];
  end

  // 2. Bộ đệm mẫu. Sau khi nhận x[n], x_delay[0] giữ x[n].
  logic signed [W_IN-1:0] x_delay [0:N_TAPS-1];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (integer k = 0; k < N_TAPS; k = k + 1) x_delay[k] <= '0;
    end else if (in_valid && in_ready) begin
      x_delay[0] <= x;
      for (integer k = 1; k < N_TAPS; k = k + 1)
        x_delay[k] <= x_delay[k-1];
    end
  end

  // 3. Dùng chung bộ nhân: acc_next = acc + h[tap] * x_delay[tap].
  logic busy;
  logic [$clog2(N_TAPS+1)-1:0] tap;
  logic signed [W_ACC-1:0] acc, product, acc_next;
  assign product = h[tap] * x_delay[tap];
  assign acc_next = acc + product;

  // 4. Điều khiển: nhận mẫu -> tap 0 -> tap 1 -> ... -> tap cuối -> output.
  assign in_ready = rst_n && !busy;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;
      tap <= '0;
      acc <= '0;
      y <= '0;
      out_valid <= 1'b0;
    end else begin
      out_valid <= 1'b0;
      if (in_valid && in_ready) begin
        busy <= 1'b1;
        tap <= '0;
        acc <= '0;
      end else if (busy) begin
        if (tap == N_TAPS-1) begin
          // Phải cộng cả tích CUỐI, vì acc chưa chứa tích này.
          y <= finish_sample(acc_next);
          out_valid <= 1'b1;
          busy <= 1'b0;
        end else begin
          acc <= acc_next;
          tap <= tap + 1'b1;
        end
      end
    end
  end

  // Fixed-point output: y = saturate((sum + rounding_bias) >>> F_COEF).
  // Signed assignment extends the sign automatically; no manual concatenation.
  localparam logic signed [W_ACC:0] ONE = 1;
  localparam logic signed [W_ACC:0] ROUND_BIAS =
      (F_COEF == 0) ? 0 : (ONE <<< (F_COEF - 1));
  localparam logic signed [W_ACC:0] MAX_OUT = (ONE <<< (W_OUT - 1)) - 1;
  localparam logic signed [W_ACC:0] MIN_OUT = -(ONE <<< (W_OUT - 1));

  function automatic logic signed [W_OUT-1:0] finish_sample(
      input logic signed [W_ACC-1:0] sum);
    logic signed [W_ACC:0] scaled;
    begin
      scaled = sum;
      scaled = (scaled + ROUND_BIAS) >>> F_COEF;
      if      (scaled > MAX_OUT) finish_sample = MAX_OUT;
      else if (scaled < MIN_OUT) finish_sample = MIN_OUT;
      else                       finish_sample = scaled;
    end
  endfunction
endmodule
