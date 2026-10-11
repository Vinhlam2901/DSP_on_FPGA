module triangle_wave_generator #(
  parameter int WIDTH = 8 // Độ phân giải bit của sóng tam giác
)(
  input  logic                   clk,      // Xung nhịp hệ thống
  input  logic                   rst_n,    // Reset tích cực mức thấp
  input  logic                   ena,      // Tín hiệu cho phép đếm (enable)
  output logic [WIDTH-1:0]       triangle_out // Ngõ ra sóng tam giác
);
  logic up_down_dir; // 0: Đếm lên (tăng), 1: Đếm xuống (giảm)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      triangle_out <= '0;
      up_down_dir  <= 1'b0;
    end else if (ena) begin
      if (up_down_dir == 1'b0) begin
        // Đếm lên cho đến khi đạt giá trị lớn nhất
        if (triangle_out == {(WIDTH){1'b1}}) begin
            up_down_dir  <= 1'b1;
            triangle_out <= triangle_out - 1'b1;
        end else begin
            triangle_out <= triangle_out + 1'b1;
        end
      end else begin
        // Đếm xuống cho đến khi về 0
        if (triangle_out == '0) begin
            up_down_dir  <= 1'b0;
            triangle_out <= triangle_out + 1'b1;
        end else begin
            triangle_out <= triangle_out - 1'b1;
        end
      end
    end
  end
endmodule