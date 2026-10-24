
// ============================================================================
module i2s_tx_24bit (
	input  logic        clk,
	input  logic        rst_n,
	input  logic [23:0] wave_in,
	output logic        bclk,
	output logic        lrclk,
	output logic        sdata
);
	localparam integer DIV_BCLK = 2;
	localparam integer CNT_W    = (DIV_BCLK <= 1) ? 1 : $clog2(DIV_BCLK);
	logic [CNT_W-1:0] bclk_div_cnt;
	// Position of the NEXT bit prepared on a BCLK falling edge:
	//  0..31  = LEFT slot
	// 32..63  = RIGHT slot
	logic [5:0] bit_pos;
	// Kept visible for debugging/full-wrapper TB.
	logic [23:0] frame_sample;
	logic [23:0] left_shift;
	logic [23:0] right_shift;
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			bclk_div_cnt <= '0;
			bclk         <= 1'b0;
			lrclk        <= 1'b0;
			sdata        <= 1'b0;
			bit_pos      <= 6'd0;
			frame_sample <= 24'd0;
			left_shift   <= 24'd0;
			right_shift  <= 24'd0;
		end
		else if (bclk_div_cnt == DIV_BCLK-1) begin
			bclk_div_cnt <= '0;
			if (bclk == 1'b0) begin
				// ------------------------------------------------------------
				// Rising BCLK:
				// WM8731 samples SDATA here.
				// No audio-data state is modified here.
				// ------------------------------------------------------------
				bclk <= 1'b1;
			end else begin
				// ------------------------------------------------------------
				// Falling BCLK:
				// Prepare LRCLK + SDATA for the NEXT rising BCLK.
				// ------------------------------------------------------------
				bclk  <= 1'b0;
				lrclk <= (bit_pos >= 6'd32);
				case (bit_pos)
					// --------------------------------------------------------
					// LEFT slot
					// --------------------------------------------------------
					// I2S one-bit delay + latch a coherent frame sample.
					6'd0: begin
						frame_sample <= wave_in;
						left_shift   <= wave_in;
						right_shift  <= wave_in;
						sdata        <= 1'b0;
					end
					// 24 LEFT data bits, MSB first.
					6'd1,  6'd2,  6'd3,  6'd4,
					6'd5,  6'd6,  6'd7,  6'd8,
					6'd9,  6'd10, 6'd11, 6'd12,
					6'd13, 6'd14, 6'd15, 6'd16,
					6'd17, 6'd18, 6'd19, 6'd20,
					6'd21, 6'd22, 6'd23, 6'd24: begin
						sdata      <= left_shift[23];
						left_shift <= {left_shift[22:0], 1'b0};
					end
					// LEFT zero padding.
					6'd25, 6'd26, 6'd27, 6'd28,
					6'd29, 6'd30, 6'd31: begin
						sdata <= 1'b0;
					end
					// --------------------------------------------------------
					// RIGHT slot
					// --------------------------------------------------------
					// I2S one-bit delay.
					6'd32: begin
						sdata <= 1'b0;
					end
					// 24 RIGHT data bits, MSB first.
					6'd33, 6'd34, 6'd35, 6'd36,
					6'd37, 6'd38, 6'd39, 6'd40,
					6'd41, 6'd42, 6'd43, 6'd44,
					6'd45, 6'd46, 6'd47, 6'd48,
					6'd49, 6'd50, 6'd51, 6'd52,
					6'd53, 6'd54, 6'd55, 6'd56: begin
						sdata       <= right_shift[23];
						right_shift <= {right_shift[22:0], 1'b0};
					end
					// RIGHT zero padding.
					default: begin
						sdata <= 1'b0;
					end
				endcase
				if (bit_pos == 6'd63)
					bit_pos <= 6'd0;
				else
					bit_pos <= bit_pos + 6'd1;
			end
		end
		else begin
			bclk_div_cnt <= bclk_div_cnt + 1'b1;
		end
	end
endmodule



