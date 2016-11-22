`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////
// Create Date:    14:47:34 05/16/2014 
// Module Name:    SD_read 
// Description: 
// Revision: 
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////
module SD_read(   
			rst,
			SD_clk,
			init_i,
			reg_rca,
			SD_cmd_en,
			SD_cmd,
			SD_cmd_resp,
			
			sec,
			read_req,
			
			data0_in,
			data1_in,
			data2_in,
			data3_in,
			
			read_state,
			reg_state,
			
			mydata_o,
			myvalid_o,
			data_come,
			data_busy
			
    );
		input  SD_clk;			// fppʱ��
		input  rst;		   	// ��λ
		input  init_i;			// ��ʼ�����
		input	[15:0] reg_rca;// RCA��ַ
		output SD_cmd_en;	   // SD CMD���ʹ��
		output SD_cmd;			// SD CMD���
		input  SD_cmd_resp;	// SD ����
		
		input [31:0] sec;  // ����ʼ��ַ,��blockΪ��λ //SD address
		input read_req;	 // ������ ÿ��������32blocks
		
		input data0_in;	// ��������
		input data1_in;
		input data2_in;
		input data3_in;
		
		output read_state; // SD��״̬���ж�SD���������Ƿ�ɹ�
		output [31:0] reg_state; // SD��״̬
		
		output [3:0]mydata_o; 
		output myvalid_o;
		output data_come; // 
		output data_busy;
											

parameter CMD7	 	= {8'h47,8'hAA,8'hAA,8'h00,8'h00,8'hcd};	// �л������ݴ���ģʽ R1p	//0xAAAA, will be replaced
parameter CMD55  	= {8'h77,8'h00,8'h00,8'h00,8'h00,8'h65};	// Ӧ�������л�
parameter ACMD6 	= {8'h46,8'h00,8'h00,8'h00,8'h02,8'hcb};	// �ı��������߿��

// SD2.0Э�鲻֧��CMD23����
//parameter CMD23	= {8'h57,8'h00,8'h00,8'h00,8'h20,8'h4B};	// ������������Χ	//32 blocks for reading
parameter CMD18	= {8'h52,8'h00,8'h00,8'h40,8'h40,8'hff};	// ������	//0x00004040 = 00408000 address/512, for test only
parameter CMD12 	= {8'h4C,8'h00,8'h00,8'h00,8'h00,8'h61};	// ��ֹͣ


/////**************** init�ӳ�,�л�ʱ��ʱ���ܴ���һ��ʱ�����ڵĲ��� *************/////
	reg init_d1;
	reg init_d2;
	always @(posedge SD_clk)
		if(rst) begin
			init_d1	<= 0;
			init_d2	<= 0;
		end
		else begin
			init_d1	<= init_i;
			init_d2	<= init_d1;
		end

/////**************** ����״̬�� *************/////
parameter	READ_IDLE	= 0,
				SEND_CMD7	= 1,
				WAIT_ACKR1B	= 2,
				GET_RESPR1B	= 3,
				WAIT_NRC		= 4, // ������������֮��ļ��
				SEND_CMD55	= 5,
				WAIT_ACKR1	= 6,
				GET_RESPR1	= 7,
				WAIT_NRC2	= 8,
				SEND_ACMD6	= 9,
//				SEND_CMD23	= 13, // 
			   READ_RDY		= 10, // ������״̬
				SEND_CMD18	= 11,
				WAIT_DATA	= 12, // �ȴ�����
				READ_DATA	= 13, // ���ݶ�ȡ				
				READ_WAIT	= 14, // �л���һ��block				
				SEND_CMD12	= 15,
				READ_FAILD	= 16, // SD����ʧ��
				READ_FINISH	= 17; // SD����ͣ�������ݴ���״̬
				

/* synthesis syn_keep = 1 */ reg [17:0] c_state;
/* synthesis syn_keep = 1 */ reg [17:0] n_state;

	wire	send_over;
	reg	nrc_timeup;
	reg	time_out;	// ������������Ӧ
	wire	ack_start;
	reg	resp_fine;
	reg	rx_valid;
	reg [2:0] nrc_state;
	reg [2:0] state_cnt;
	reg   data_start;
	reg   read_end;
	reg	read_one_block;
	
	always @(posedge SD_clk)
		if(rst)
			c_state	<= 'd1;
		else
			c_state	<= n_state;
	
	always @ (*)
		begin
			n_state <= 'd0;
			case(1'b1)
				c_state[READ_IDLE]:	// ��ʼ����ɣ��л������ݴ���ģʽ
					if(init_d2)
						n_state[SEND_CMD7] <= 1'b1;
					else						
						n_state[READ_IDLE] <= 1'b1;						
				
				c_state[SEND_CMD7]: // ѡ�������봫��ģʽ
					if(send_over)
						n_state[WAIT_ACKR1B] <= 1'b1;
					else
						n_state[SEND_CMD7] <= 1'b1;	
				
				c_state[WAIT_ACKR1B]: // ��������������NCC������ 
					if(time_out)	// ����ʱ�䣨100ms������Ӧ�������
						n_state[READ_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR1B] <= 1'b1;					
					else						
						n_state[WAIT_ACKR1B] <= 1'b1;
						
				c_state[GET_RESPR1B]:
					if(rx_valid & resp_fine)	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[WAIT_NRC] <= 1'b1;
					else if(rx_valid & ~resp_fine) // ��Ӧ����ȷ�����ʧ��
						n_state[READ_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR1B] <= 1'b1;
						
				c_state[WAIT_NRC]: // ��һ����Ӧ����һ������֮����NRC
					if(nrc_timeup & nrc_state==3'd0) // ��һ��������CMD7ʱ
						n_state[SEND_CMD55] <= 1'b1;
					else if(nrc_timeup & nrc_state==3'd1) // ��һ��������CMD12ʱ,��32��blocks���
						n_state[READ_FINISH] <= 1'b1;
					else
						n_state[WAIT_NRC] <= 1'b1;
						
				c_state[SEND_CMD55]:	// ����Ӧ��ָ���ӦΪR1b
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_CMD55] <= 1'b1;
				
				c_state[WAIT_ACKR1]:
					if(time_out)	// ����ʱ������Ӧ�����ʼ��ʧ��
						n_state[READ_FAILD] <= 1'b1;
					else if(ack_start) // ��⵽CMD�����ͣ�����Ӧ��ʼ
						n_state[GET_RESPR1] <= 1'b1;					
					else						
						n_state[WAIT_ACKR1] <= 1'b1;				
				
				c_state[GET_RESPR1]:
					if(rx_valid & resp_fine )	// ��Ӧ��ȷ���ȴ�NRC���ں�����һ������
						n_state[WAIT_NRC2] <= 1'b1;
					else if(rx_valid & ~resp_fine) // ��Ӧ����ȷ�����ʧ��
						n_state[READ_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR1] <= 1'b1;
				
				c_state[WAIT_NRC2]: // ��һ����Ӧ����һ������֮����NRC
					if(nrc_timeup & state_cnt==3'd0) // ������������CMD55
						n_state[SEND_ACMD6] <= 1'b1;
					else if(nrc_timeup & state_cnt==3'd1 ) // ������������ACMD6,��ȴ�������
						n_state[READ_RDY] <= 1'b1;			
					else if(nrc_timeup & state_cnt==3'd2) // ������������CMD18,��ȴ�����
						n_state[WAIT_DATA] <= 1'b1;				
					else
						n_state[WAIT_NRC2] <= 1'b1;
												
				c_state[SEND_ACMD6]:	// ����Ӧ��ָ���ӦΪR1 // �л���������ģʽ
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_ACMD6] <= 1'b1;
										
//				c_state[SEND_CMD23]:	// 
//					if(send_over)
//						n_state[WAIT_ACKR2] <= 1'b1;
//					else
//						n_state[SEND_CMD23] <= 1'b1;				

				c_state[READ_RDY]:	// ��ȫ׼����,��ʱ���Զ�
					if(read_req)
						n_state[SEND_CMD18] <= 1'b1;
					else
						n_state[READ_RDY] <= 1'b1;
						
				c_state[SEND_CMD18]:	// ���Ϳ������ 
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_CMD18] <= 1'b1;
						
				c_state[WAIT_DATA]:
					if(time_out)	// ����ʱ������Ӧ���������
						n_state[READ_FAILD] <= 1'b1;
					else if(data_start)	// ���ݿ�ʼ��
						n_state[READ_DATA] <= 1'b1;						
					else					
						n_state[WAIT_DATA] <= 1'b1;
				
				c_state[READ_DATA]:
					if(read_one_block)	// ����һ��block 32��blocks 32*512B = 4*1024
						n_state[READ_WAIT] <= 1'b1;						
					else					
						n_state[READ_DATA] <= 1'b1;
						
				c_state[READ_WAIT]:
					if(read_end)	// ����32��blocks 32*512B = 4*1024
						n_state[SEND_CMD12] <= 1'b1;						
					else if(data_start)	// ��һ��block���ݿ�ʼ��				
						n_state[READ_DATA] <= 1'b1;
					else
						n_state[READ_WAIT] <= 1'b1;
				
				c_state[SEND_CMD12]:	// ����RCA����
					if(send_over)
						n_state[WAIT_ACKR1B] <= 1'b1;
					else
						n_state[SEND_CMD12] <= 1'b1;				
						
				c_state[READ_FAILD]:	// ��ʧ�ܴ������������¿�ʼ
//					if(try_cnt)
//						n_state[SEND_CMD0] <= 1'b1;
//					else
						n_state[READ_IDLE] <= 1'b1;
						
				c_state[READ_FINISH]:	// һ�ζ������ɣ��ȴ��´ζ�
						n_state[READ_RDY] <= 1'b1;						
						
				default:
						n_state[READ_IDLE] <= 1'b1;	
			endcase
		end
	
	
	/////**************** ״̬����ת���� *************/////

	// ��������,ʱ�ָ���
	wire [6:0]CRC_o;
	reg [5:0] tx_cnt;
	
/* synthesis syn_keep = 1 */	reg [47:0] tx_cmd;
	always @(posedge SD_clk)		
		if(rst)
			tx_cmd	<= 'd0;
		else begin
			case	(1'b1)
				c_state[SEND_CMD7]	: begin
					if(tx_cnt==6'd42)
						tx_cmd <= {8'h47,reg_rca,8'h00,8'h00,CRC_o,1'b1};
					else
						tx_cmd <= tx_cmd;
			    end
				 
				c_state[SEND_CMD55]	: begin
					if(tx_cnt==6'd42)
						tx_cmd <= {8'h77,reg_rca,8'h00,8'h00,CRC_o,1'b1};
					else
						tx_cmd <= tx_cmd;
			    end
				 
				c_state[SEND_ACMD6]	: tx_cmd <= ACMD6;
				
				c_state[SEND_CMD18]	: begin
					if(tx_cnt==6'd42)
						tx_cmd <= {8'h52,sec,CRC_o,1'b1};
					else
						tx_cmd <= tx_cmd;
			    end
				 
				c_state[SEND_CMD12]	: tx_cmd <= CMD12;
				
				default					: tx_cmd <= tx_cmd;
			endcase
		end
	
//	reg	tx_valid;
//	always @(posedge SD_clk)		
//		if(rst)
//			tx_valid	<= 'd0;
//		else 
//			tx_valid	<= c_state[SEND_CMD7] 	| c_state[SEND_CMD55] | c_state[SEND_ACMD6]
//						 | c_state[SEND_CMD18]	| c_state[SEND_CMD12];
	wire 	 tx_validw;
	assign tx_validw =   c_state[SEND_CMD7] 	| c_state[SEND_CMD55] | c_state[SEND_ACMD6]
						   | c_state[SEND_CMD18]	| c_state[SEND_CMD12];
	
//	reg [15:0] tx_valid_delay;
//	always @(posedge SD_clk)
//		tx_valid_delay <= {tx_valid_delay[14:0],tx_validw};
		
//	reg [5:0] tx_cnt;
	always @(posedge SD_clk)		
		if(rst)
			tx_cnt	<= 'd0;
		else if( tx_validw & (tx_cnt<6'd60) )
			tx_cnt	<= tx_cnt + 1'd1;
		else if( tx_validw & (tx_cnt==6'd60) )
			tx_cnt	<= tx_cnt;
		else
			tx_cnt	<= 'd0;
	
	 
	reg [47:0] cmd_tmp;
	always @(posedge SD_clk)		
		if(rst)
			cmd_tmp	<= 'd0;
		else if(c_state[SEND_CMD7] & tx_cnt==6'd0)
			cmd_tmp	<= {8'h47,reg_rca,8'h00,8'h00,8'hff};
		else if(c_state[SEND_CMD55] & tx_cnt==6'd0)
			cmd_tmp	<= {8'h77,reg_rca,8'h00,8'h00,8'hff};
		else if(c_state[SEND_CMD18] & tx_cnt==6'd0)
			cmd_tmp	<= {8'h52,sec,8'hff};
		else //if((c_state[SEND_CMD7]|c_state[SEND_CMD55]|c_state[SEND_CMD18]) & (tx_cnt>6'd0 & tx_cnt<=6'd39))
			cmd_tmp	<= {cmd_tmp[46:0],1'b1};
			
	reg CRC_In;
	always @(posedge SD_clk)		
		if(rst)
			CRC_In	<= 'd0;
		else 
			CRC_In	<= cmd_tmp[47];		
	
	reg CRC_En;
	always @(posedge SD_clk)		
		if(rst)
			CRC_En	<= 'd0;
		else 
			CRC_En	<= (c_state[SEND_CMD7]|c_state[SEND_CMD55]|c_state[SEND_CMD18])& (tx_cnt>6'd0 & tx_cnt<=6'd41);
		
//	wire [6:0]CRC_o;
	CRC_7 CRC_7_u(
				.CLK(SD_clk), 
				.RST(rst), 
				.BITVAL(CRC_In), 
				.Enable(CRC_En), 
				.CRC(CRC_o));

//	wire	tx_valid = (tx_cnt>=6'd42);
	reg 	tx_valid;
	always @(posedge SD_clk)		
		if(rst)
			tx_valid	<= 'd0;
		else 
			tx_valid <= (tx_cnt>6'd44);
	

	wire 	SD_cmd_en;
	wire 	SD_cmd;
//	wire	send_over;
	sd_cmd_tx sd_cmd_tx_u (
		 .clk(SD_clk), 
		 .rst(rst), 
		 .tx_valid(tx_valid), 
		 .tx_cmd(tx_cmd),
		 .cmd_out_en(SD_cmd_en),
		 .cmd_out(SD_cmd),
		 .tx_over(send_over)
    );

	// ����������Ӧ,ʱ�ָ���
	
	// cmd �����Ӧ��ʼ
//	assign	ack_start = ~SD_cmd_resp;
	
/* synthesis syn_keep = 1 */	reg [47:0] rx_resp; 
	always @(posedge SD_clk) 
		rx_resp  <={rx_resp[46:0],SD_cmd_resp};	

	assign	ack_start = (rx_resp[1:0] == 2'b0);
	
	reg 	rx_en;
	always @(posedge SD_clk) 
		if(rst)
			rx_en <= 0;
		else 
			rx_en <= c_state[GET_RESPR1B] | c_state[GET_RESPR1]; //| c_state[GET_RESPR2]
	
	reg [5:0] rx_cnt;
	always @(posedge SD_clk) 
		if(rst) 
			rx_cnt <= 'd0;
		else if(rx_en & rx_cnt<=6'd45)
			rx_cnt <= rx_cnt +1'b1;
		else
			rx_cnt <= 'd0;
			
	reg  		 rx_finish;
	always @(posedge SD_clk) 
		if(rst) 
			rx_finish <= 'd0;
		else if(rx_en)
			rx_finish <= (rx_cnt==6'd43);
		else
			rx_finish <= 'd0;
		
	reg [47:0] rx_data;
	always @(posedge SD_clk) 
		if(rst) 
			rx_data <= 'd0;
		else if(rx_finish)
			rx_data <= rx_resp;
	
//	reg [15:0] rx_delay;
//	always @(posedge SD_clk) 
//		rx_delay <= {rx_delay[14:0],rx_finish};
	
	//	reg  rx_valid;
	always @(posedge SD_clk) 
		if(rst) 
			rx_valid <= 0;
		else if(rx_en)
			rx_valid <= (rx_cnt==6'd45);
			
// �ж���Ӧ�Ƿ���ȷ
///	reg	resp_fine; // ��ʱ����
	always @(posedge SD_clk) 
		if(rst) 
			resp_fine <= 'd0;
		else begin
			case(1'b1)
				c_state[GET_RESPR1B] : begin
					if(nrc_state==3'd0 & (rx_data[45:40]==6'd7)) //CMD7  & (rx_data[20:17]==4'd4)
						resp_fine <= 1'b1;
					else if(nrc_state==3'd1 & (rx_data[45:40]==6'd12)) //CMD12 
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;						
				end
				
				c_state[GET_RESPR1] : begin
					if(state_cnt==3'd0 & (rx_data[45:40]==6'd55)) //CMD55 
						resp_fine <= 1'b1;
					else if(state_cnt==3'd1 & (rx_data[45:40]==6'd6)) //ACMD6 
						resp_fine <= 1'b1;
					else if(state_cnt==3'd2 & (rx_data[45:40]==6'd18)) //CMD18
						resp_fine <= 1'b1;
					else
						resp_fine <= 1'd0;	
				end
				default:	
						resp_fine <= resp_fine;
						
			endcase
		end

		
	// NRCNRC=NCC=16�ݶ�
	reg [4:0] nrc_cnt;
	always @(posedge SD_clk) 
		if(rst) 
			nrc_cnt <= 'd0;
		else if(c_state[WAIT_NRC]|c_state[WAIT_NRC2])
			nrc_cnt <= nrc_cnt + 1'b1;
		else
			nrc_cnt <= 'd0;
	
//	reg	nrc_timeup;
	always @(posedge SD_clk) 
		if(rst) begin
			nrc_timeup <= 0;
		end
		else begin
			nrc_timeup <= (nrc_cnt==5'd16);
		end
	
	// �ȴ�SD����Ӧ������ 100ms��ʱ
	reg [31:0] wait_cnt;
	always @(posedge SD_clk) 
		if(rst) 
			wait_cnt <= 'd0;
		else if(c_state[WAIT_ACKR1B]|c_state[WAIT_ACKR1])
			wait_cnt <= wait_cnt + 1'b1;
		else
			wait_cnt <= 'd0;
	
//	reg 	time_out;
	always @(posedge SD_clk) 
		if(rst)
			time_out <= 0;
		else 
			time_out <= (wait_cnt==32'd625000);
			
	// nrc_state,state_cnt
	//	reg [2:0] nrc_state; // 1=�Ѿ�����CMD7 2=�Ѿ�����CMD12
	always @(posedge SD_clk) 
		if(rst)
			nrc_state <= 'd0;
		else if(c_state[READ_IDLE])
			nrc_state <= 'd0;			
		else if(c_state[READ_FINISH])
			nrc_state <= 3'd1;
		else if(c_state[WAIT_NRC] & nrc_timeup)			
			nrc_state <= nrc_state + 'd1;
		
	//	reg [2:0] nrc_state; // 1=�Ѿ�����CMD55 2=�Ѿ�����ACMD6 3=�Ѿ�����CMD18
	always @(posedge SD_clk) 
		if(rst)
			state_cnt <= 'd0;
		else if(c_state[READ_IDLE])
			state_cnt <= 'd0;
		else if(c_state[READ_FINISH])	 //һ�ζ���ɣ��ص��շ���ACMD6֮���״̬	
			state_cnt <= 3'd2;
		else if(c_state[WAIT_NRC2] & nrc_timeup)			
			state_cnt <= state_cnt + 'd1;
			
	reg [3:0] mydata_delay1; 
	reg [3:0] mydata_delay2; 
	reg [3:0] mydata_delay3; 
	always @(posedge SD_clk) 
		if(rst) begin
			mydata_delay1	<= 'd0;
			mydata_delay2	<= 'd0;
			mydata_delay3	<= 'd0;
		end
		else begin
			mydata_delay1	<= mydata;
			mydata_delay2	<= mydata_delay1;
			mydata_delay3	<= mydata_delay2;
		end
				
			
//	reg data_start; 
	always @(posedge SD_clk) 
		if(rst)
			data_start <= 'b0;
		else if((~data3_in & ~data2_in & ~data1_in & ~data0_in) & data_come 
					& mydata_delay1==4'hf & mydata_delay2==4'hf & mydata_delay3==4'hf) // ���Ͷ������ & ~data_busy
			data_start <= 1'b1;	//
		else
			data_start <= 'b0;
			
//	reg	read_one_block; 
	always @(posedge SD_clk) 
		if(rst)
			read_one_block <= 'b0;
		else if(valid_cnt[9:0]==10'd1022) // ���Ͷ������
			read_one_block <= 1'b1;	// ���������״�Ϊ0ʱ
		else
			read_one_block <= 'b0;
			
//	reg	data_start;
	always @(posedge SD_clk) 
		if(rst)
			read_end <= 'b0; //����32K�������
		else if(valid_cnt==20'd262143) //16kB = 32*1024�� //128KB = 128*1024 *2 = 262144 halfByte
			read_end <= 1'b1;
		else
			read_end <= 'b0;
			
	
	/////**************** ��� *************/////
	reg	read_state; // ʧ��һ�Σ�������ߵ�ƽ
	always @(posedge SD_clk) 
		if(rst)
			read_state <= 1'd0;
		else if(c_state[READ_FAILD])			
			read_state <= 1'd1;
			
	reg [31:0] reg_state; // ʧ��һ�Σ�������ߵ�ƽ
	always @(posedge SD_clk) 
		if(rst)
			reg_state <= 'd0;
		else //if(c_state[READ_FAILD])			
			reg_state <= rx_data[39:8];
	
	reg	data_come; // ���ݵ������,��������������
	always @(posedge SD_clk) 
		if(rst)
			data_come <= 1'd0;
		else if(c_state[SEND_CMD18] & send_over)	//	��������������	
			data_come <= 1'd1;
		else if(c_state[SEND_CMD12])	// ���������
			data_come	<= 'd0;
			
	reg	data_busy; // ��ʼ��������1������ɹ���
	always @(posedge SD_clk) 
		if(rst)
			data_busy <= 1'd0;
		else if(c_state[READ_DATA])			
			data_busy <= 1'd1;
		else if((c_state[READ_FINISH]))
			data_busy <= 1'd0;
		
	
	reg [19:0] valid_cnt;
	always @(posedge SD_clk) 
		if(rst) 
			valid_cnt	<= 'd0;
		else if(c_state[READ_DATA])
			valid_cnt	<= valid_cnt + 1'b1;
		else if(c_state[READ_FINISH] | c_state[READ_IDLE])
			valid_cnt	<= 'd0;		
			
	reg [3:0] mydata; 
	always @(posedge SD_clk) 
		if(rst) 
			mydata	<= 'd0;
		else 
			mydata	<= {data3_in,data2_in,data1_in,data0_in};	
	
/* synthesis syn_keep = 1 */	reg [3:0] mydata_o; 
	always @(posedge SD_clk) 
		if(rst) 
			mydata_o	<= 'd0;
		else 
			mydata_o	<= mydata;
			
	reg  	    myvalid_o;	
	always @(posedge SD_clk) 
		if(rst) begin
			myvalid_o <= 'd0;
		end	
		else  begin
			myvalid_o <= (c_state[READ_DATA] & valid_cnt<=20'd262143);// (c_state[READ_DATA] & valid_cnt<=16'd32767);
		end
		
endmodule
