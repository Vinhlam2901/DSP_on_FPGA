module button_debouncer #(
  parameter int WAIT_CYCLES = 500_000
)(
  input  logic clk,
  input  logic rst_n,
  input  logic btn_in,
  output logic btn_tick
);
  localparam int CNT_W = (WAIT_CYCLES <= 1) ? 1 : $clog2(WAIT_CYCLES);
  // Thuộc tính dành cho Quartus.
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
  logic btn_sync_0, btn_sync_1;
  logic btn_state;
  logic [CNT_W-1:0] counter;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      btn_sync_0 <= 1'b1;
      btn_sync_1 <= 1'b1;
    end else begin
      btn_sync_0 <= btn_in;
      btn_sync_1 <= btn_sync_0;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      btn_state <= 1'b1;
      counter   <= '0;
      btn_tick  <= 1'b0;
    end else begin
      btn_tick <= 1'b0;
      if (btn_sync_1 == btn_state) begin
        counter <= '0;
      end else if (counter == WAIT_CYCLES - 1) begin
        counter   <= '0;
        btn_state <= btn_sync_1;
        // Nút active-low: chỉ phát tick khi xác nhận nhấn.
        btn_tick <= ~btn_sync_1;
      end else begin
        counter <= counter + 1'b1;
      end
    end
  end
endmodule
