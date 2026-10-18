module hex_decoder #(
  parameter bit COMMON_ANODE = 1'b1 // 1: Anode chung (mức 0 sáng), 0: Cathode chung (mức 1 sáng)
)(
  input  logic [3:0] bin,
  output logic [6:0] hex
);

  logic [6:0] decoded_hex;

  always_comb begin
    case (bin)
      // Mã mặc định dành cho Anode chung (Active Low)
      4'h0: decoded_hex = 7'b1000000;
      4'h1: decoded_hex = 7'b1111001;
      4'h2: decoded_hex = 7'b0100100;
      4'h3: decoded_hex = 7'b0110000;
      4'h4: decoded_hex = 7'b0011001;
      4'h5: decoded_hex = 7'b0010010;
      4'h6: decoded_hex = 7'b0000010;
      4'h7: decoded_hex = 7'b1111000;
      4'h8: decoded_hex = 7'b0000000;
      4'h9: decoded_hex = 7'b0010000;
      default: decoded_hex = 7'b1111111; // Tắt LED (toàn 1)
    endcase
  end

  // Nếu là Anode chung thì giữ nguyên, nếu Cathode chung thì đảo toàn bộ các bit
  assign hex = COMMON_ANODE ? decoded_hex : ~decoded_hex;

endmodule