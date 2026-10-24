# ==============================================================================
# 1. BIẾN CẤU HÌNH (PARAMETERS & MARGINS)
# ==============================================================================
# Khai báo Margin trước (Bù trừ hao hụt cho đường dây PCB, nhiệt độ)
set SETUP_MARGIN 0.5
set HOLD_MARGIN  0.5

# Khai báo tần số và tính toán chu kỳ có bù trừ Margin (Over-constrain)
# Ép Quartus tối ưu cho chu kỳ 19.5ns thay vì 20ns
set FPGA_FREQ    50.0
set FPGA_PERIOD  [expr {(1000.0 / $FPGA_FREQ) - $SETUP_MARGIN}]

set CODEC_FREQ   12.288
set CODEC_PERIOD [expr {(1000.0 / $CODEC_FREQ) - $SETUP_MARGIN}]

# Thông số Datasheet WM8731
set WM8731_tDST  10.0 ;             # Setup time yêu cầu của chip CODEC
set WM8731_tDHT  10.0 ;             # Hold time yêu cầu của chip CODEC
set WM8731_tDDA  35.0 ;             # Trễ dữ liệu tối đa từ CODEC truyền ra

# ==============================================================================
# 2. KHAI BÁO XUNG NHỊP (CLOCKS)
# ==============================================================================
# Tạo clock gốc 50MHz sử dụng biến đã tính toán
create_clock -name clk_50m -period $FPGA_PERIOD [get_ports {CLOCK_50}]

# Yêu cầu Quartus tự động nội suy clock từ PLL
derive_pll_clocks

# Khai báo xung nhịp 12.288 MHz xuất ra chân vật lý AUD_XCK
create_generated_clock -name AUD_XCK_out \
    -source [get_pins {pll_inst|pll_12_288mhz_inst|altera_pll_i|outclk[0]}] \
    [get_ports {AUD_XCK}]

# Tự động tính toán Clock Jitter (Mặc định của Altera/Intel)
derive_clock_uncertainty

# ==============================================================================
# 3. XỬ LÝ GIAO TIẾP LIÊN MIỀN (CLOCK DOMAIN CROSSING)
# ==============================================================================
# Báo cho Quartus biết miền 50MHz và toàn bộ miền PLL 12.288MHz là độc lập
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {pll_inst|pll_12_288mhz_inst|altera_pll_i|outclk[0] AUD_XCK_out}]
# ==============================================================================
# 4. RÀNG BUỘC NGÕ RA (OUTPUT DELAYS) CÓ KÈM MARGIN
# ==============================================================================
# Tính toán Delay Max/Min (Cộng thêm Margin để "ép" công cụ định tuyến chạy kỹ hơn)
# Max delay (Setup): Yêu cầu CODEC + Biên an toàn
set out_delay_max [expr $WM8731_tDST + $SETUP_MARGIN]
# Min delay (Hold): Yêu cầu CODEC + Biên an toàn (Tính theo số âm)
set out_delay_min [expr -($WM8731_tDHT + $HOLD_MARGIN)]

set_output_delay -clock [get_clocks {AUD_XCK_out}] -max $out_delay_max [get_ports {AUD_DACDAT AUD_DACLRCK AUD_BCLK}]
set_output_delay -clock [get_clocks {AUD_XCK_out}] -min $out_delay_min [get_ports {AUD_DACDAT AUD_DACLRCK AUD_BCLK}]

# ==============================================================================
# 5. RÀNG BUỘC NGÕ VÀO (INPUT DELAYS) CÓ KÈM MARGIN
# ==============================================================================
# Input Delay Max = Độ trễ từ CODEC + Biên an toàn
set in_delay_max [expr $WM8731_tDDA + $SETUP_MARGIN]

set_input_delay -clock [get_clocks {AUD_XCK_out}] -max $in_delay_max [get_ports {AUD_ADCDAT}]
set_input_delay -clock [get_clocks {AUD_XCK_out}] -min 0.0 [get_ports {AUD_ADCDAT}]

# ==============================================================================
# 6. LOẠI BỎ PHÂN TÍCH TIMING (FALSE PATHS)
# ==============================================================================
# Các tín hiệu tương tác tay hoặc hiển thị chậm
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX*}]

# Đường cấu hình I2C tốc độ thấp
set_false_path -to   [get_ports {FPGA_I2C_SCLK FPGA_I2C_SDAT}]
set_false_path -from [get_ports {FPGA_I2C_SDAT}]