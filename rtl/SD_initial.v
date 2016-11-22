`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Create Date:    14:47:34 05/16/2014 
// Module Name:    SD_initial 
// Description: 
// Revision: 
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////
`define DO_CRC
module SD_initial(
		rst,
		SD_clk,
		SD_clk_init,
		SD_trig,
		SD_cmd_en,
		SD_cmd,
		SD_cmd_resp,
		init_o,
		
		reg_cid,
		reg_ocr,
		reg_sta,
		reg_rca
);
		input rst; 		//  reset
		input SD_clk; // 6.25MHz
		output SD_clk_init; 	// ��ʼ��ʱ��SD���ʱ��
		input	 SD_trig;		// SD�������ź�
		output SD_cmd_en;  	// CMDʹ�ܣ�������̬���
		output SD_cmd; 		// CMD���
		input  SD_cmd_resp;  // CMD����
		output init_o;	// ��ʼ�����
		
		output [126:0] reg_cid; // ���ص�ǰCID�Ĵ�����ֵ
		output [31:0] reg_ocr; // ���ص�ǰOCR�Ĵ�����ֵ
		output [15:0] reg_sta; // ���ص�ǰ��״̬��ֵ
		output [15:0] reg_rca; // ���ص�ǰ����RCA��ַ

				
/////**************** ��������������� *************/////

//							��ʼ01 ����� ���� CRC7  1
parameter  CMD0 	= {2'b01,6'd0,32'b0,7'h4a,1'b1};  // ��λ
parameter  CMD8 	= {8'h48,8'h00,8'h00,8'h01,8'haa,8'h87};	// ��ѹ���
parameter  CMD55	= {8'h77,8'h00,8'h00,8'h00,8'h00,8'h65};	// Ӧ�������л�
parameter  ACMD41	= {8'h69,8'h40,8'h10,8'h00,8'h00,8'hcd};	// ���Ϳ���֧����Ϣ
//parameter  ACMD41	= {8'h69,8'h40,8'hff,8'h80,8'h00,8'h17};	// ���Ϳ���֧����Ϣ
//parameter  ACMD41={8'h69,8'h50,8'h3F,8'h00,8'h00,8'h97};
parameter  CMD2	= {8'h42,8'h00,8'h00,8'h00,8'h00,8'h4d};	// ����CID����
parameter  CMD3	= {8'h43,8'h00,8'h00,8'h00,8'h00,8'h21};  // ����RCA����


/////**************** ��Ƶ����400KHzʱ�ӳ�ʼ��ʱ�� *************/////		
/*
reg [3:0] clkCount;
always @(posedge SD_clk) 
	if(rst)
		clkCount <= 'd0;
	else
		clkCount <= clkCount + 1'b1;
		
reg 		 clk_init=1'b0;		//SD init clock generate
always @(posedge SD_clk) 		//SD_clk=50M
	 if(clkCount==4'd8)		
		clk_init	<= ~clk_init;
	else
		clk_init <= clk_init;
*/
	
assign	SD_clk_init = SD_clk;

/////**************** ����Ŀ�ʱ����ͬ�� *************/////
reg 		 SD_trig_d1;
reg 		 SD_trig_d2;
always @(posedge SD_clk_init)
	 if(rst)	begin
			SD_trig_d1 <= 0;
			SD_trig_d2 <= 0;
	end
	else begin
			SD_trig_d1 <= SD_trig;
			SD_trig_d2 <= SD_trig_d1;
  end

reg 		 SD_trig_d3;
reg 		 SD_trig_d4;
always @(posedge SD_clk_init)
	 if(rst)	begin
			SD_trig_d3 <= 0;
			SD_trig_d4 <= 0;
	end
	else begin
			SD_trig_d3 <= SD_trig_d2;
			SD_trig_d4 <= SD_trig_d3;
  end
		
reg	SD_trig_sop;
always @(posedge SD_clk_init)
	 if(rst)	
			SD_trig_sop <= 0;
	 else
			SD_trig_sop <= SD_trig_d3 & ~SD_trig_d4;
			
		
/////**************** ����״̬�� *************/////
parameter	INIT_IDLE	= 0,
				SEND_CMD0	= 1,
				WAIT_NCC		= 2, // ������������֮��ļ��
				SEND_CMD8	= 3,
				WAIT_ACKR7	= 4,
				GET_RESPR7	= 5,
				WAIT_NRC		= 6,
				SEND_CMD55	= 7,
				WAIT_ACKR1	= 8,
				GET_RESPR1	= 9,
				WAIT_NRC2	= 10,
				SEND_ACMD41	= 11,
				WAIT_ACKR3	= 12,
				GET_RESPR3	= 13,
				WAIT_NRC3	= 14,
				SEND_CMD2	= 15,
				WAIT_ACKR2	= 16,
				GET_RESPR2	= 17,
				WAIT_NRC4	= 18,
				SEND_CMD3	= 19,
				WAIT_ACKR6	= 20,
				GET_RESPR6	= 21,
				INIT_DONE	= 22,
				INIT_FAILD	= 23;
				
/* synthesis syn_keep = 1 */ reg [23:0] c_state;
/* synthesis syn_keep = 1 */ reg [23:0] n_state;
	
	reg 	timeup_1ms;
	wire	send_over;
	reg	ncc_timeup;
	reg	nrc_timeup;
	reg	time_out;
/* synthesis syn_keep = 1 */	wire	ack_start;
	reg	resp_fine;
	reg	rx_valid;
	reg	rx_valid2;
	reg	rx_valid6;
	
	always @(posedge SD_clk_init)
		if(rst)
			c_state	<= 24'd1;
		else
			c_state	<= n_state;
	
	always @ (*)
		begin
			n_state <= 'd0;
			case(1'b1)
				c_state[INIT_IDLE]:	// �ϵ��ӳ�1ms��ʼ��ʼ��
					if(timeup_1ms & SD_trig_sop)
						n_state[SEND_CMD0] <= 1'b1;
					else						
						n_state[INIT_IDLE] <= 1'b1;						
				
				c_state[SEND_CMD0]: // ���ͳ�ʼ���������Ӧ
					if(send_over)
						n_state[WAIT_NCC] <= 1'b1;
					else
						n_state[SEND_CMD0] <= 1'b1;	
				
				c_state[WAIT_NCC]: // ��������������NCC������ 
					if(ncc_timeup)
						n_state[SEND_CMD8] <= 1'b1;
					else
						n_state[WAIT_NCC] <= 1'b1;
						
				c_state[SEND_CMD8]: // ���͵�ѹ��������ӦR7
					if(send_over)
						n_state[WAIT_ACKR7] <= 1'b1;
					else
						n_state[SEND_CMD8] <= 1'b1;
				
				c_state[WAIT_ACKR7]:
					if(time_out)	// ����ʱ������Ӧ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR7] <= 1'b1;					
					else						
						n_state[WAIT_ACKR7] <= 1'b1;				
				
				c_state[GET_RESPR7]:
					if(rx_valid & resp_fine)	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[WAIT_NRC] <= 1'b1;
					else if(rx_valid & ~resp_fine) // ��Ӧ����ȷ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR7] <= 1'b1;
				
				c_state[WAIT_NRC]: // ��һ����Ӧ����һ������֮����NRC
					if(nrc_timeup)
						n_state[SEND_CMD55] <= 1'b1;
					else
						n_state[WAIT_NRC] <= 1'b1;
						
				c_state[SEND_CMD55]:	// ����Ӧ��ָ���ӦΪR1
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_CMD55] <= 1'b1;
				
				c_state[WAIT_ACKR1]:
					if(time_out)	// ����ʱ������Ӧ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR1] <= 1'b1;					
					else						
						n_state[WAIT_ACKR1] <= 1'b1;				
				
				c_state[GET_RESPR1]:
					if(rx_valid & resp_fine)	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[WAIT_NRC2] <= 1'b1;
					else if(rx_valid & ~resp_fine) // ��Ӧ����ȷ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR1] <= 1'b1;
				
				c_state[WAIT_NRC2]: // ��һ����Ӧ����һ������֮����NRC
					if(nrc_timeup)
						n_state[SEND_ACMD41] <= 1'b1;
					else
						n_state[WAIT_NRC2] <= 1'b1;
						
				c_state[SEND_ACMD41]:	// ����Ӧ��ָ���ӦΪR3
					if(send_over)
						n_state[WAIT_ACKR3] <= 1'b1;
					else
						n_state[SEND_ACMD41] <= 1'b1;
				
				c_state[WAIT_ACKR3]:
					if(time_out)	// ����ʱ������Ӧ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR3] <= 1'b1;					
					else						
						n_state[WAIT_ACKR3] <= 1'b1;				
				
				c_state[GET_RESPR3]:
					if(rx_valid & resp_fine)	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[WAIT_NRC3] <= 1'b1;
					else if(rx_valid & ~resp_fine) // ��Ӧ����ȷ�������·��� ACMD41(CMD55)
						n_state[WAIT_NRC] <= 1'b1;						
					else					
						n_state[GET_RESPR3] <= 1'b1;
						
				c_state[WAIT_NRC3]: // ��һ����Ӧ����һ������֮����NRC
					if(nrc_timeup)
						n_state[SEND_CMD2] <= 1'b1;
					else
						n_state[WAIT_NRC3] <= 1'b1;
						
				c_state[SEND_CMD2]:	// ����CID����
					if(send_over)
						n_state[WAIT_ACKR2] <= 1'b1;
					else
						n_state[SEND_CMD2] <= 1'b1;
				
				c_state[WAIT_ACKR2]:
					if(time_out)	// ����ʱ������Ӧ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR2] <= 1'b1;					
					else						
						n_state[WAIT_ACKR2] <= 1'b1;				
				
				c_state[GET_RESPR2]:
					if(rx_valid2 & resp_fine)	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[WAIT_NRC4] <= 1'b1;
					else if(rx_valid2 & ~resp_fine) // ��Ӧ����ȷ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR2] <= 1'b1;
						
				c_state[WAIT_NRC4]: // ��һ����Ӧ����һ������֮����NRC
					if(nrc_timeup)
						n_state[SEND_CMD3] <= 1'b1;
					else
						n_state[WAIT_NRC4] <= 1'b1;
						
				c_state[SEND_CMD3]:	// ����RCA����
					if(send_over)
						n_state[WAIT_ACKR6] <= 1'b1;
					else
						n_state[SEND_CMD3] <= 1'b1;
				
				c_state[WAIT_ACKR6]:
					if(time_out)	// ����ʱ������Ӧ�����ʼ��ʧ��
						n_state[INIT_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR6] <= 1'b1;					
					else						
						n_state[WAIT_ACKR6] <= 1'b1;				
				
				c_state[GET_RESPR6]:
					if(rx_valid6 & resp_fine)	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[INIT_DONE] <= 1'b1;
					else if(rx_valid6 & ~resp_fine) // ��Ӧ����ȷ�����ʼ��ʧ�� //���·���CMD3
						n_state[INIT_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR6] <= 1'b1;
						
				c_state[INIT_FAILD]:	// ��ʼ��ʧ�ܴ������������³�ʼ��
//					if(try_cnt)
//						n_state[SEND_CMD0] <= 1'b1;
//					else
						n_state[INIT_IDLE] <= 1'b1;
						
					
				c_state[INIT_DONE]:	// ��ʼ����ɣ������ɱ��
						n_state[INIT_IDLE] <= 1'b1;	
					
						
				default:
						n_state[INIT_IDLE] <= 1'b1;	
			endcase
		end
	
	
	/////**************** ״̬����ת���� *************/////
	// �ϵ��ӳ�1ms	
	reg [9:0] init_cnt;
	always @(posedge SD_clk_init)		
		if(rst)
			init_cnt	<= 0;
		else if(c_state[INIT_IDLE] & init_cnt<10'd1023)
			init_cnt	<= init_cnt + 1'b1;
						
	always @(posedge SD_clk_init)		
		if(rst)
			timeup_1ms	<= 0;
		else 
			timeup_1ms	<= (init_cnt==10'd1023);
	
	// ��������,ʱ�ָ���
	reg [47:0] tx_cmd;
	always @(posedge SD_clk_init)		
		if(rst)
			tx_cmd	<= 'd0;
		else begin
			case	(1'b1)
				c_state[SEND_CMD0]	: tx_cmd <= CMD0;
				c_state[SEND_CMD8]	: tx_cmd <= CMD8;
				c_state[SEND_CMD55]	: tx_cmd <= CMD55;
				c_state[SEND_ACMD41]	: tx_cmd <= ACMD41;
				c_state[SEND_CMD2]	: tx_cmd <= CMD2;
				c_state[SEND_CMD3]	: tx_cmd <= CMD3;
				default	:	tx_cmd <= tx_cmd;
			endcase
		end
	
	reg	tx_valid;
	always @(posedge SD_clk_init)		
		if(rst)
			tx_valid	<= 'd0;
		else 
			tx_valid	<= c_state[SEND_CMD0] 	| c_state[SEND_CMD8] | c_state[SEND_CMD55]
						 | c_state[SEND_ACMD41]	| c_state[SEND_CMD2]	| c_state[SEND_CMD3];
	
	wire 	SD_cmd_en;
	wire 	SD_cmd;
//	wire	send_over;
	sd_cmd_tx sd_cmd_tx_u (
		 .clk(SD_clk_init), 
		 .rst(rst), 
		 .tx_valid(tx_valid), 
		 .tx_cmd(tx_cmd),
		 .cmd_out_en(SD_cmd_en),
		 .cmd_out(SD_cmd),
		 .tx_over(send_over)
    );

	
	// ����������Ӧ,ʱ�ָ���
	
	// cmd ���2��ʱ����Ӧ��ʼ
//	assign	ack_start = ~SD_cmd_resp;
	
/* synthesis syn_keep = 1 */	reg [47:0] rx_resp; 
	always @(posedge SD_clk_init) 
		rx_resp  <={rx_resp[46:0],SD_cmd_resp};	

	assign	ack_start = (rx_resp[1:0]==2'b00);
	
	reg 	rx_en;
	always @(posedge SD_clk_init) 
		if(rst)
			rx_en <= 0;
		else 
			rx_en <= c_state[GET_RESPR7] | c_state[GET_RESPR1] | c_state[GET_RESPR3]
					 | c_state[GET_RESPR6]; //| c_state[GET_RESPR2]
	
	reg [5:0] rx_cnt;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_cnt <= 'd0;
		else if(rx_en & rx_cnt<=6'd60)
			rx_cnt <= rx_cnt +1'b1;
		else
			rx_cnt <= 'd0;
			
	reg  		 rx_finish;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_finish <= 'd0;
		else if(rx_en)
			rx_finish <= (rx_cnt==6'd43);
		else
			rx_finish <= 'd0;
		
	/* synthesis syn_keep = 1 */reg [47:0] rx_data;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_data <= 'd0;
		else if(rx_finish)
			rx_data <= rx_resp;

//	reg [15:0] rx_delay;
//	always @(posedge SD_clk_init) 
//		rx_delay <= {rx_delay[14:0],rx_finish};
		
	//	reg  rx_valid;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_valid <= 0;
		else if(rx_en)
			rx_valid <= (rx_cnt==6'd45);
			
	//	reg  rx_valid;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_valid6 <= 0;
		else if(rx_en)
			rx_valid6 <= (rx_resp[47:40]==8'h03);
			
	reg [47:0] rx_data6;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_data6 <= 'd0;
		else if(rx_en & (rx_resp[47:40]==8'h03))
			rx_data6 <= rx_resp;
			
	
	// R2����������Ӧ
	reg 	rx_en2;
	always @(posedge SD_clk_init) 
		if(rst)
			rx_en2 <= 0;
		else 
			rx_en2 <= c_state[GET_RESPR2];
	
	reg [7:0] rx_cnt2;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_cnt2 <= 'd0;
		else if(rx_en2 & rx_cnt2<=8'd133)
			rx_cnt2 <= rx_cnt2 +1'b1;
		else
			rx_cnt2 <= 'd0;
	
	reg [135:0] rx_resp2; 
	always @(posedge SD_clk_init) 
		rx_resp2  <={rx_resp2[134:0],SD_cmd_resp};	
			
	
	/* synthesis syn_keep = 1 */reg [135:0] rx_data2; 
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_data2 <= 'd0;
		else if(rx_en2 & rx_cnt2==8'd132)
			rx_data2 <= rx_resp2;
	
//	reg  rx_valid2;
	always @(posedge SD_clk_init) 
		if(rst) 
			rx_valid2 <= 0;
		else if(rx_en2)
			rx_valid2 <= (rx_cnt2==8'd133);
			
	// �ж���Ӧ�Ƿ���ȷ
///	reg	resp_fine;
	always @(posedge SD_clk_init) 
		if(rst) 
			resp_fine <= 'd0;
		else begin
			case(1'b1)
				c_state[GET_RESPR7] : begin
					if( (rx_data[45:40]==6'd8) & (rx_data[19:16]==4'b0001)) // �ӿڵ�ѹΪ2.7~3.6V
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;
				end
				
				c_state[GET_RESPR1] : begin
					if(rx_data[45:40]==6'd55) // crcУ����ȷ
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;
				end
				
				c_state[GET_RESPR3] :begin // �����ж�
					if( (rx_data[45:40]==6'h3f) & (rx_data[39:38]==2'b11)) // busy=1��ccs=1					
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;						
				end
				
				c_state[GET_RESPR2] : begin // �����ж�
					if(rx_data2[133:128]==6'h3f) // //crcУ����ȷ
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;							
				end
						
				c_state[GET_RESPR6] : begin
					if(rx_data6[45:40]==6'h3) // //crcУ����ȷ
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;
				end
			endcase
		end

		
	// NRC��NCC������ NRC=NCC=16�ݶ�
	reg [4:0] ncc_cnt;
	always @(posedge SD_clk_init) 
		if(rst) 
			ncc_cnt <= 'd0;
		else if(c_state[WAIT_NCC]|c_state[WAIT_NRC]|c_state[WAIT_NRC2]|c_state[WAIT_NRC3]|c_state[WAIT_NRC4])
			ncc_cnt <= ncc_cnt + 1'b1;
		else
			ncc_cnt <= 'd0;
	
	always @(posedge SD_clk_init) 
		if(rst) begin
			ncc_timeup <= 0;
			nrc_timeup <= 0;
		end
		else begin
			ncc_timeup <= (ncc_cnt==5'd16);
			nrc_timeup <= (ncc_cnt==5'd16);
		end
	
	// �ȴ�SD����Ӧ������ 100ms��ʱ
	reg [31:0] wait_cnt;
	always @(posedge SD_clk_init) 
		if(rst) 
			wait_cnt <= 'd0;
		else if(c_state[WAIT_ACKR7]|c_state[WAIT_ACKR1]|c_state[WAIT_ACKR3]|c_state[WAIT_ACKR2]|c_state[WAIT_ACKR6])
			wait_cnt <= wait_cnt + 1'b1;
		else
			wait_cnt <= 'd0;
	
	always @(posedge SD_clk_init) 
		if(rst)
			time_out <= 0;
		else 
			time_out <= (wait_cnt==32'd40000);

	

	/////**************** ��� *************/////
	reg 	init_o; // ��ʼ�����
	always @(posedge SD_clk_init) 
		if(rst) 
			init_o <= 0;
		else if(c_state[INIT_DONE])
			init_o <= 1'b1;
	
	reg [126:0] reg_cid;
	always @(posedge SD_clk_init) 
		if(rst) 
			reg_cid <= 0;
		else  //if(c_state[GET_RESPR2] & rx_valid2)
			reg_cid <= rx_data2[127:1];
	
	reg [31:0] reg_ocr;
	always @(posedge SD_clk_init) 
		if(rst) 
			reg_ocr <= 0;
		else  if(c_state[GET_RESPR3] & rx_valid)
			reg_ocr <= rx_data[39:8];
	
	reg [15:0] reg_sta;
	always @(posedge SD_clk_init) 
		if(rst) 
			reg_sta <= 0;
		else  if(c_state[GET_RESPR6] & rx_valid6)
			reg_sta <= rx_data6[23:8];
			
	reg [15:0] reg_rca;
	always @(posedge SD_clk_init) 
		if(rst) 
			reg_rca <= 0;
		else  if(c_state[GET_RESPR6] & rx_valid6)
			reg_rca <= rx_data6[39:24];
	
endmodule
