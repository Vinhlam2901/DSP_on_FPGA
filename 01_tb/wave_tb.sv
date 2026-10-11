module wave_tb;

  // Khai báo tín hiệu
  logic               clk;
  logic               rst_n;
  logic [31:0]        tuning_word;
  logic [1:0]         amp_control;
  logic [1:0]         wave_sel;
  logic signed [7:0]  wave_out;

  // Khởi tạo DUT (Device Under Test)
  // Cài PHASE_WIDTH = 8 cho dễ test (256 mẫu)
  generator_wave #(
      .PHASE_WIDTH(10),
      .DATA_WIDTH(8)
  ) dut (
      .clk         (clk),
      .rst_n       (rst_n),
      .tuning_word (tuning_word),
      .amp_control (amp_control),
      .wave_sel    (wave_sel),
      .wave_out    (wave_out)
  );

  // Tạo Clock 50MHz (Chu kỳ 20ns)
  initial begin
      clk = 0;
      forever #10 clk = ~clk;
  end

  // Cấu hình ghi file sóng cho SimVision
  initial begin
      $shm_open("wave.shm");
      $shm_probe(wave_tb, "ACMTF"); 
  end
  // Kịch bản mô phỏng
  initial begin
      $display("[%0t] Starting Simulation...", $time);
      // Giá trị khởi tạo
      rst_n       = 0;
      amp_control = 2'b10;        // Biên độ 100%
      tuning_word = 32'd16777216; // Tần số để quét hết 1 chu kỳ sóng sau 256 xung clock
      wave_sel    = 2'b00;        // Mặc định Sine
      #45; rst_n = 1;
      // 1. Chạy Sóng Sine (wave_sel = 00)
      $display("[%0t] Testing SINE wave", $time);
      #20000; 
      // 2. Chuyển sang Sóng Tam Giác (wave_sel = 01)
      @(posedge clk);
      wave_sel = 2'b01; 
      $display("[%0t] Testing TRIANGLE wave", $time);
      #20000;
      // 3. Chuyển sang Sóng Răng Cưa (wave_sel = 10)
      @(posedge clk);
      wave_sel = 2'b10;
      $display("[%0t] Testing SAWTOOTH wave", $time);
      #20000;
      // 4. Chuyển sang Sóng ECG (wave_sel = 11)
      // Lưu ý: Nếu file ecg_data.hex chưa có hoặc bị lỗi, sóng này sẽ xuất hiện giá trị 'X'
      @(posedge clk);
    //   wave_sel = 2'b11;
    //   $display("[%0t] Testing ECG wave", $time);
    //   #20000;
      $display("[%0t] Simulation Finished.", $time);
      $shm_close();
      $finish;
  end
endmodule