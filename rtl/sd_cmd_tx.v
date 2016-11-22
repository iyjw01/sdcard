`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    08:18:45 03/29/2015 
// Design Name: 
// Module Name:    sd_cmd_tx 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module sd_cmd_tx(
			clk,
			rst,
			tx_valid,
			tx_cmd,
			cmd_out_en,
			cmd_out,
			tx_over
    );
input			 clk;
input			 rst;
input			 tx_valid;	//电平 高有效
input [47:0] tx_cmd;
output		 cmd_out_en;
output		 cmd_out;
output		 tx_over;

	reg [5:0] cmd_cnt;
	
/* synthesis syn_keep = 1 */	reg [47:0] cmd_tmp;
	always @(posedge clk)
		if(rst)
			cmd_tmp <= 'd0;
		else if(cmd_cnt==6'd1) // tx_valid上升沿取数
			cmd_tmp <= tx_cmd;
		else if(cmd_cnt>6'd1)
			cmd_tmp <= {cmd_tmp[46:0],1'b1};			
			
	always @(posedge clk)
		if(rst)
			cmd_cnt <= 'd0;
		else if(tx_valid)
			cmd_cnt <= cmd_cnt + 1'b1;
		else
			cmd_cnt <= 'd0;
	
	
	reg  cmd_out_en;
	always @(posedge clk)
		if(rst)
			cmd_out_en <= 0;
		else
			cmd_out_en <= (cmd_cnt>6'd0 & cmd_cnt<=6'd48);
			
	
	reg  cmd_out;
	always @(posedge clk)
		if(rst)
			cmd_out <= 'd1;
		else if(cmd_cnt>6'd1)
			cmd_out <= cmd_tmp[47];
		else
			cmd_out <= 'd1;
	
	reg  tx_over;
	always @(posedge clk)
		if(rst)
			tx_over <= 'd0;
		else
			tx_over <= (cmd_cnt==6'd49);


endmodule
