module button_debouncer #(
  parameter int WAIT_CYCLES = 500_000
)(
  input  logic clk,
  input  logic rst_n,
  input  logic btn_in,
  output logic btn_tick
);
  logic [19:0] counter;
  logic btn_sync_0, btn_sync_1, btn_state;
  // Dò cạnh (Edge Detection)
  assign btn_tick = (btn_sync_1 && ~btn_sync_0) && (counter == '0);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      btn_sync_0 <= 1'b1; 
      btn_sync_1 <= 1'b1; 
      btn_state  <= 1'b1;
      counter    <= '0;
    end else begin
      // 2-stage synchronizer
      btn_sync_0 <= btn_in;
      btn_sync_1 <= btn_sync_0;
      if (btn_sync_1 != btn_state) begin
        counter <= WAIT_CYCLES; 
        btn_state <= btn_sync_1;
      end else if (counter > 0) begin
        counter <= counter - 1;
      end
    end
  end
endmodule