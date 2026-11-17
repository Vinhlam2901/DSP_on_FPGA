// IIR folded: one multiplier reused for the five terms of each biquad.
// Order: +b0*u, +b1*x1, +b2*x2, -a1*y1, -a2*y2; then update state.
module iir_folded #(
  parameter integer N_SECTIONS = 3,
  parameter integer W_IN = 24,
  parameter integer W_OUT = 24,
  parameter integer W_COEF = 18,
  parameter integer F_COEF = 16,
  parameter integer INPUT_SHIFT = 2,
  parameter integer W_STATE = W_IN + INPUT_SHIFT,
  parameter integer W_ACC = W_STATE + W_COEF + 3,
  // Low to high: s0 b0,b1,b2,a1,a2; s1 b0,... . a0 is normalized to 1.
  parameter logic [N_SECTIONS*5*W_COEF-1:0] COEFFS = '0
)(
  input logic clk,
  input logic rst_n, // asynchronous assertion; release synchronously to clk
  input logic in_valid,
  output logic in_ready,
  input logic signed [W_IN-1:0] x,
  output logic out_valid,
  output logic signed [W_OUT-1:0] y
);

  // 1. ROM hệ số. Tên mảng trùng với công thức biquad.
  wire signed [W_COEF-1:0] b0 [0:N_SECTIONS-1];
  wire signed [W_COEF-1:0] b1 [0:N_SECTIONS-1];
  wire signed [W_COEF-1:0] b2 [0:N_SECTIONS-1];
  wire signed [W_COEF-1:0] a1 [0:N_SECTIONS-1];
  wire signed [W_COEF-1:0] a2 [0:N_SECTIONS-1];
  for (genvar s = 0; s < N_SECTIONS; s = s + 1) begin : coefficients
    assign b0[s] = COEFFS[(s*5+0)*W_COEF +: W_COEF];
    assign b1[s] = COEFFS[(s*5+1)*W_COEF +: W_COEF];
    assign b2[s] = COEFFS[(s*5+2)*W_COEF +: W_COEF];
    assign a1[s] = COEFFS[(s*5+3)*W_COEF +: W_COEF];
    assign a2[s] = COEFFS[(s*5+4)*W_COEF +: W_COEF];
  end

  // 2. Mỗi section có bộ thanh ghi trễ riêng.
  logic signed [W_STATE-1:0] x1 [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] x2 [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] y1 [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] y2 [0:N_SECTIONS-1];
  logic signed [W_STATE-1:0] u; // input hiện tại của section đang tính
  wire signed [W_STATE-1:0] x_extended;
  assign x_extended = x;

  logic busy;
  logic [$clog2(N_SECTIONS+1)-1:0] section;
  typedef enum logic [2:0] {B0_U, B1_X1, B2_X2, A1_Y1, A2_Y2} step_t;
  step_t step;

  // 3. Mux chọn hai ngõ vào của MỘT bộ nhân theo từng tích trong công thức.
  logic signed [W_COEF-1:0] coefficient;
  logic signed [W_STATE-1:0] sample;
  logic subtract;
  always_comb begin
    coefficient = '0;
    sample = '0;
    subtract = 1'b0;
    case (step)
      B0_U:  begin coefficient = b0[section]; sample = u;           end
      B1_X1: begin coefficient = b1[section]; sample = x1[section]; end
      B2_X2: begin coefficient = b2[section]; sample = x2[section]; end
      A1_Y1: begin coefficient = a1[section]; sample = y1[section]; subtract = 1'b1; end
      A2_Y2: begin coefficient = a2[section]; sample = y2[section]; subtract = 1'b1; end
      default: begin end
    endcase
  end

  // 4. MAC dùng chung và output section. Tích signed tự mở rộng dấu.
  logic signed [W_ACC-1:0] product, acc, acc_next;
  wire signed [W_STATE-1:0] section_output;
  assign product = coefficient * sample;
  assign acc_next = subtract ? acc - product : acc + product;
  assign section_output = finish_section(acc_next);

  // 5. Điều khiển: nhận mẫu -> năm tích -> section tiếp theo hoặc output.
  assign in_ready = rst_n && !busy;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;
      section <= '0;
      step <= B0_U;
      acc <= '0;
      u <= '0;
      y <= '0;
      out_valid <= 1'b0;
      for (integer s = 0; s < N_SECTIONS; s = s + 1) begin
        x1[s] <= '0;
        x2[s] <= '0;
        y1[s] <= '0;
        y2[s] <= '0;
      end
    end else begin
      out_valid <= 1'b0;
      if (in_valid && in_ready) begin
        u <= x_extended <<< INPUT_SHIFT;
        section <= '0;
        step <= B0_U;
        acc <= '0;
        busy <= 1'b1;
      end else if (busy) begin
        acc <= acc_next;
        case (step)
          B0_U:  step <= B1_X1;
          B1_X1: step <= B2_X2;
          B2_X2: step <= A1_Y1;
          A1_Y1: step <= A2_Y2;
          A2_Y2: begin
            // Tính xong năm tích mới được cập nhật state của section này.
            x1[section] <= u;
            x2[section] <= x1[section];
            y1[section] <= section_output;
            y2[section] <= y1[section];
            acc <= '0;
            step <= B0_U;
            if (section == N_SECTIONS-1) begin
              y <= finish_sample(section_output);
              out_valid <= 1'b1;
              busy <= 1'b0;
            end else begin
              u <= section_output;
              section <= section + 1'b1;
            end
          end
          default: step <= B0_U;
        endcase
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
