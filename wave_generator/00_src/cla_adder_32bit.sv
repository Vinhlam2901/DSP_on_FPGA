module cla_adder_32bit (
	input  wire [31:0] a_i,
	input  wire [31:0] b_i,
	input  wire        cin_i,
	output reg         cout_o,
	output reg  [31:0] result_o 
);
//===============DECLARATION=====================================================================================
  wire [7:0] prog_temp, gen_ntemp;
	wire [7:0] cin_out;
	wire       p_o, g_no;
//===============RESUTL_PROCESS==========================================================================================
	cla_adder_4bit cla_0 (.a_i(a_i[3:0]  ),.b_i(b_i[3:0]  ),.cin_i(cin_i     ),.cout_o(cin_out[0]),.result_o(result_o[3:0]  ));
	cla_adder_4bit cla_1 (.a_i(a_i[7:4]  ),.b_i(b_i[7:4]  ),.cin_i(cin_out[0]),.cout_o(cin_out[1]),.result_o(result_o[7:4]  ));
	cla_adder_4bit cla_2 (.a_i(a_i[11:8] ),.b_i(b_i[11:8] ),.cin_i(cin_out[1]),.cout_o(cin_out[2]),.result_o(result_o[11:8] ));
	cla_adder_4bit cla_3 (.a_i(a_i[15:12]),.b_i(b_i[15:12]),.cin_i(cin_out[2]),.cout_o(cin_out[3]),.result_o(result_o[15:12]));
	cla_adder_4bit cla_4 (.a_i(a_i[19:16]),.b_i(b_i[19:16]),.cin_i(cin_out[3]),.cout_o(cin_out[4]),.result_o(result_o[19:16]));
	cla_adder_4bit cla_5 (.a_i(a_i[23:20]),.b_i(b_i[23:20]),.cin_i(cin_out[4]),.cout_o(cin_out[5]),.result_o(result_o[23:20]));
	cla_adder_4bit cla_6 (.a_i(a_i[27:24]),.b_i(b_i[27:24]),.cin_i(cin_out[5]),.cout_o(cin_out[6]),.result_o(result_o[27:24]));
	cla_adder_4bit cla_7 (.a_i(a_i[31:28]),.b_i(b_i[31:28]),.cin_i(cin_out[6]),.cout_o(cin_out[7]),.result_o(result_o[31:28]));
	always_comb begin : carry_out
		cout_o = cin_out[7];
	end
endmodule