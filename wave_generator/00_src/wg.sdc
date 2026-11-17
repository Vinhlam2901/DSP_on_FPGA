# Real clock periods; add timing margin through uncertainty, not frequency.
create_clock -name clk_50m -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks
set pll_out [get_pins {pll_inst|pll_12_288mhz_inst|altera_pll_i|outclk[0]}]
create_generated_clock -name AUD_XCK_out -source $pll_out [get_ports {AUD_XCK}]
# i2s_tx_24bit toggles BCLK every two MCLK cycles.
create_generated_clock -name AUD_BCLK_out -source $pll_out -divide_by 4 [get_ports {AUD_BCLK}]
derive_clock_uncertainty

# Codec samples serial data/LRCLK on rising BCLK. Includes 0.5 ns margin.
set_output_delay -clock AUD_BCLK_out -max 10.5 [get_ports {AUD_DACDAT AUD_DACLRCK}]
set_output_delay -clock AUD_BCLK_out -min -10.5 [get_ports {AUD_DACDAT AUD_DACLRCK}]

# PLL and reference clocks remain related. Cut only asynchronous control
# inputs at the FIRST synchronizer stage; later stages remain timed.
set_false_path -from [get_registers {*|cfg_req}] -to [get_registers {*|req_sync[0]}]
set_false_path -from [get_registers {*|cfg_ack}] -to [get_registers {*|ack_sync[0]}]
# cfg_hold is held until ACK. The destination captures after two request
# synchronizer stages. Bound bus routing below one 81.38 ns MCLK period.
set_max_delay -datapath_only 60.0 -from [get_registers {*|cfg_hold[*]}] -to [get_registers {*|par_12[*]}]

# Physical asynchronous inputs. No blanket clock-group exception.
set_false_path -from [get_ports {KEY[*] SW[*]}]
# PLL lock drives only reset assertion (release is synchronized per domain).
set_false_path -from [get_pins {pll_inst|pll_12_288mhz_inst|altera_pll_i|locked}] -to [get_registers {*|rst12_sr[*] *|cfg50_reset_sr[*]}]
set_false_path -to [get_ports {LEDR[*] HEX*}]
# Low-speed I2C is verified separately; no ADC input exists in this top.
set_false_path -to [get_ports {FPGA_I2C_SCLK FPGA_I2C_SDAT}]
set_false_path -from [get_ports {FPGA_I2C_SDAT}]
