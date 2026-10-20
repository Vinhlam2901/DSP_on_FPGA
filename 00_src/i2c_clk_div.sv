// 12.288 MHz system clock: DIV=16 -> SCL = 12.288 MHz / (2*(16+1)) = 361.412 kHz.
module i2c_clk_div #(
    parameter integer DIV = 16
) (
    input  logic clk,
    input  logic reset_n,
    output logic scl_out
);
    localparam integer CNT_W = (DIV < 1) ? 1 : $clog2(DIV + 1);
    logic [CNT_W-1:0] cnt;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt     <= '0;
            scl_out <= 1'b1;
        end else if (cnt == DIV) begin
            cnt     <= '0;
            scl_out <= ~scl_out;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end
endmodule
