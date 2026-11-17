`timescale 1ns / 1ps

module tb_DE10_Standard_golden_top;

  // =======================================================
  // 1. THÔNG SỐ VÀ CẤU HÌNH MÔ PHỎNG
  // =======================================================
  localparam int PHASE_WIDTH = 10;
  localparam int DATA_WIDTH  = 24;

  // Xung clock 50MHz -> Chu kỳ = 20ns
  localparam real CLK50_PERIOD = 20.0;

  // Tần số mặc định sau reset là DEF_FREQ = 1000 Hz
  // 1 chu kỳ dạng sóng = 1 / 1000Hz = 1 ms = 1_000_000 ns
  localparam real WAVE_PERIOD_NS = 1_000_000.0;

  // =======================================================
  // 2. KHAI BÁO TÍN HIỆU NỐI VỚI DUT
  // =======================================================
  logic        CLOCK_50;
  logic [3:0]  KEY;
  logic [9:0]  SW;
  logic [9:0]  LEDR;
  logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
  logic        FPGA_I2C_SCLK;
  wire         FPGA_I2C_SDAT;
  logic        AUD_XCK;
  logic        AUD_BCLK;
  logic        AUD_DACLRCK;
  logic        AUD_DACDAT;

  // Trở kéo lên (Pull-up) cho đường bus I2C
  pullup (FPGA_I2C_SDAT);
  // pullup (FPGA_I2C_SCLK);

  // =======================================================
  // 3. INSTANTIATE DUT (DESIGN UNDER TEST)
  // =======================================================
  DE10_Standard_golden_top #(
    .PHASE_WIDTH(PHASE_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) dut (
    .CLOCK_50     (CLOCK_50),
    .KEY          (KEY),
    .SW           (SW),
    .LEDR         (LEDR),
    .HEX0         (HEX0),
    .HEX1         (HEX1),
    .HEX2         (HEX2),
    .HEX3         (HEX3),
    .HEX4         (HEX4),
    .HEX5         (HEX5),
    .FPGA_I2C_SCLK(FPGA_I2C_SCLK),
    .FPGA_I2C_SDAT(FPGA_I2C_SDAT),
    .AUD_XCK      (AUD_XCK),
    .AUD_BCLK     (AUD_BCLK),
    .AUD_DACLRCK  (AUD_DACLRCK),
    .AUD_DACDAT   (AUD_DACDAT)
  );

  // =======================================================
  // 4. TẠO XUNG CLOCK 50MHz
  // =======================================================
  initial begin
    CLOCK_50 = 0;
    forever #(CLK50_PERIOD / 2.0) CLOCK_50 = ~CLOCK_50;
  end

  // =======================================================
  // 5. KỊCH BẢN MÔ PHỎNG (TESTCASES)
  // =======================================================
  initial begin
    // Khởi tạo trạng thái ban đầu
    KEY = 4'b1111; // Active-low: 1111 là không nhấn nút
    SW  = 10'b0;   // Tắt toàn bộ switch
    SW[1:0] = 2'b01; // Duty 50%

    // -----------------------------------------------------
    // RESET HỆ THỐNG
    // -----------------------------------------------------
    $display("[%0t ns] Bắt đầu Reset hệ thống...", $time);
    KEY[0] = 1'b0;  // Nhấn KEY0
    #(100);
    KEY[0] = 1'b1;  // Thả KEY0
    $display("[%0t ns] Đã thả Reset, chờ PLL và các miền Clock ổn định...", $time);

    // Đợi đồng bộ các miền clock
    wait (dut.rst50_n === 1'b1 && dut.rst12_n === 1'b1);
    repeat (10) @(posedge AUD_XCK);

    // =====================================================
    // TESTCASE 1: Duyệt từng dạng sóng (0 -> 7) - KHÔNG NHIỄU
    // =====================================================
    $display("\n=================================================================");
    $display("[%0t ns] TESTCASE 1: Hiện lần lượt 8 dạng sóng (5 chu kỳ/sóng) - KHÔNG NHIỄU (SW[8]=0)", $time);
    $display("=================================================================");

    SW[8] = 1'b0; // Tắt nhiễu

    for (int wave = 0; wave < 8; wave++) begin
      SW[7:5] = wave[2:0]; // Chọn dạng sóng qua SW[7:5]
      $display("[%0t ns] Mode Sóng = %0d (SW[7:5] = 3'b%03b) | Nhiễu = TẮT", $time, wave, wave[2:0]);

      // Wait for the 10 ms switch filter and the configuration handshake.
      wait (dut.sw_stable === {SW[7:5], SW[8], SW[1:0]});
      wait ({dut.wsel_12, dut.noise_12, dut.duty_12} ===
            {SW[7:5], SW[8], SW[1:0]});
      // Observe three waveform periods after configuration arrives.
      #(3 * WAVE_PERIOD_NS);
    end

    // =====================================================
    // TESTCASE 2: Duyệt từng dạng sóng (0 -> 7) - BẬT NHIỄU
    // =====================================================
    $display("\n=================================================================");
    $display("[%0t ns] TESTCASE 2: Hiện lần lượt 8 dạng sóng (5 chu kỳ/sóng) - BẬT NHIỄU (SW[8]=1)", $time);
    $display("=================================================================");

    SW[8] = 1'b1; // Bật nhiễu

    for (int wave = 0; wave < 8; wave++) begin
      SW[7:5] = wave[2:0]; // Chọn dạng sóng qua SW[7:5]
      $display("[%0t ns] Mode Sóng = %0d (SW[7:5] = 3'b%03b) | Nhiễu = BẬT", $time, wave, wave[2:0]);

      // Wait for the 10 ms switch filter and the configuration handshake.
      wait (dut.sw_stable === {SW[7:5], SW[8], SW[1:0]});
      wait ({dut.wsel_12, dut.noise_12, dut.duty_12} ===
            {SW[7:5], SW[8], SW[1:0]});
      // Observe three waveform periods after configuration arrives.
      #(3 * WAVE_PERIOD_NS);
    end

    // =====================================================
    // KẾT THÚC MÔ PHỎNG
    // =====================================================
    $display("\n=================================================================");
    $display("[%0t ns] Hoàn thành toàn bộ Testcases!", $time);
    $display("=================================================================");
    $finish;
  end

  // Ghi file VCD để quan sát waveform trên SimVision / ModelSim / GTKWave
  initial begin
    $dumpfile("wave.shm");
    $dumpvars(0, tb_DE10_Standard_golden_top);
  end

endmodule
