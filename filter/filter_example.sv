// Example wrapper using coefficients exported from the existing Python pipeline.
// Compile with +incdir+filter/coeffs (Yosys: -I filter/coeffs).
module filter_example #(
  parameter bit USE_IIR = 1'b0,
  parameter bit FOLDED = 1'b1
)(
  input logic clk, rst_n, in_valid,
  output logic in_ready,
  input logic signed [23:0] x,
  output logic out_valid,
  output logic signed [23:0] y
);
  `include "fir_params.svh"
  `include "iir_params.svh"
  if (!USE_IIR) begin : fir
    if (!FOLDED) begin : baseline
      fir_baseline #(.N_TAPS(FIR_N_TAPS), .W_IN(FIR_W_IN),
        .W_OUT(FIR_W_OUT), .W_COEF(FIR_W_COEF), .F_COEF(FIR_F_COEF),
        .W_ACC(FIR_W_ACC), .COEFFS(FIR_COEF_FLAT)) core (
          .clk(clk), .rst_n(rst_n),
          .in_valid(in_valid), .in_ready(in_ready), .x(x),
          .out_valid(out_valid), .y(y)
        );
    end else begin : folded
      fir_folded #(.N_TAPS(FIR_N_TAPS), .W_IN(FIR_W_IN),
        .W_OUT(FIR_W_OUT), .W_COEF(FIR_W_COEF), .F_COEF(FIR_F_COEF),
        .W_ACC(FIR_W_ACC), .COEFFS(FIR_COEF_FLAT)) core (
          .clk(clk), .rst_n(rst_n),
          .in_valid(in_valid), .in_ready(in_ready), .x(x),
          .out_valid(out_valid), .y(y)
        );
    end
  end else begin : iir
    if (!FOLDED) begin : baseline
      iir_baseline #(.N_SECTIONS(IIR_N_SECTIONS), .W_IN(IIR_W_IN),
        .W_OUT(IIR_W_OUT), .W_COEF(IIR_W_COEF), .F_COEF(IIR_F_COEF),
        .INPUT_SHIFT(IIR_GUARD), .W_STATE(IIR_W_STATE),
        .W_ACC(IIR_W_ACC), .COEFFS(IIR_COEF_FLAT)) core (
          .clk(clk), .rst_n(rst_n),
          .in_valid(in_valid), .in_ready(in_ready), .x(x),
          .out_valid(out_valid), .y(y)
        );
    end else begin : folded
      iir_folded #(.N_SECTIONS(IIR_N_SECTIONS), .W_IN(IIR_W_IN),
        .W_OUT(IIR_W_OUT), .W_COEF(IIR_W_COEF), .F_COEF(IIR_F_COEF),
        .INPUT_SHIFT(IIR_GUARD), .W_STATE(IIR_W_STATE),
        .W_ACC(IIR_W_ACC), .COEFFS(IIR_COEF_FLAT)) core (
          .clk(clk), .rst_n(rst_n),
          .in_valid(in_valid), .in_ready(in_ready), .x(x),
          .out_valid(out_valid), .y(y)
        );
    end
  end
endmodule
