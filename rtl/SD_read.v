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
		input  SD_clk;			// fpp时钟
		input  rst;		   	// 复位
		input  init_i;			// 初始化完成
		input	[15:0] reg_rca;// RCA地址
		output SD_cmd_en;	   // SD CMD输出使能
		output SD_cmd;			// SD CMD输出
		input  SD_cmd_resp;	// SD 输入
		
		input [31:0] sec;  // 读起始地址,以block为单位 //SD address
		input read_req;	 // 读请求 每次连续读32blocks
		
		input data0_in;	// 数据输入
		input data1_in;
		input data2_in;
		input data3_in;
		
		output read_state; // SD读状态，判断SD卡读操作是否成功
		output [31:0] reg_state; // SD卡状态
		
		output [3:0]mydata_o; 
		output myvalid_o;
		output data_come; // 
		output data_busy;
											

parameter CMD7	 	= {8'h47,8'hAA,8'hAA,8'h00,8'h00,8'hcd};	// 切换到数据传输模式 R1p	//0xAAAA, will be replaced
parameter CMD55  	= {8'h77,8'h00,8'h00,8'h00,8'h00,8'h65};	// 应用命令切换
parameter ACMD6 	= {8'h46,8'h00,8'h00,8'h00,8'h02,8'hcb};	// 改变数据总线宽度

// SD2.0协议不支持CMD23命令
//parameter CMD23	= {8'h57,8'h00,8'h00,8'h00,8'h20,8'h4B};	// 定义连续读范围	//32 blocks for reading
parameter CMD18	= {8'h52,8'h00,8'h00,8'h40,8'h40,8'hff};	// 连续读	//0x00004040 = 00408000 address/512, for test only
parameter CMD12 	= {8'h4C,8'h00,8'h00,8'h00,8'h00,8'h61};	// 读停止


/////**************** init延迟,切换时钟时可能存在一个时钟周期的差异 *************/////
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

/////**************** 控制状态机 *************/////
parameter	READ_IDLE	= 0,
				SEND_CMD7	= 1,
				WAIT_ACKR1B	= 2,
				GET_RESPR1B	= 3,
				WAIT_NRC		= 4, // 两条主机命令之间的间隔
				SEND_CMD55	= 5,
				WAIT_ACKR1	= 6,
				GET_RESPR1	= 7,
				WAIT_NRC2	= 8,
				SEND_ACMD6	= 9,
//				SEND_CMD23	= 13, // 
			   READ_RDY		= 10, // 读待命状态
				SEND_CMD18	= 11,
				WAIT_DATA	= 12, // 等待数据
				READ_DATA	= 13, // 数据读取				
				READ_WAIT	= 14, // 切换下一个block				
				SEND_CMD12	= 15,
				READ_FAILD	= 16, // SD卡读失败
				READ_FINISH	= 17; // SD卡会停留在数据传输状态
				

/* synthesis syn_keep = 1 */ reg [17:0] c_state;
/* synthesis syn_keep = 1 */ reg [17:0] n_state;

	wire	send_over;
	reg	nrc_timeup;
	reg	time_out;	// 两条命令间的响应
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
				c_state[READ_IDLE]:	// 初始化完成，切换到数据传输模式
					if(init_d2)
						n_state[SEND_CMD7] <= 1'b1;
					else						
						n_state[READ_IDLE] <= 1'b1;						
				
				c_state[SEND_CMD7]: // 选定卡进入传输模式
					if(send_over)
						n_state[WAIT_ACKR1B] <= 1'b1;
					else
						n_state[SEND_CMD7] <= 1'b1;	
				
				c_state[WAIT_ACKR1B]: // 两条主机命令间隔NCC个周期 
					if(time_out)	// 若长时间（100ms）无响应，则结束
						n_state[READ_FAILD] <= 1'b1;
					else if(ack_start) // 检测到CMD被拉低，则响应开始
						n_state[GET_RESPR1B] <= 1'b1;					
					else						
						n_state[WAIT_ACKR1B] <= 1'b1;
						
				c_state[GET_RESPR1B]:
					if(rx_valid & resp_fine)	// 响应正确，等待NRC周期后发送下一条命令
						n_state[WAIT_NRC] <= 1'b1;
					else if(rx_valid & ~resp_fine) // 响应不正确，则读失败
						n_state[READ_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR1B] <= 1'b1;
						
				c_state[WAIT_NRC]: // 上一条响应和下一条命令之间间隔NRC
					if(nrc_timeup & nrc_state==3'd0) // 上一条命令是CMD7时
						n_state[SEND_CMD55] <= 1'b1;
					else if(nrc_timeup & nrc_state==3'd1) // 上一条命令是CMD12时,读32个blocks完成
						n_state[READ_FINISH] <= 1'b1;
					else
						n_state[WAIT_NRC] <= 1'b1;
						
				c_state[SEND_CMD55]:	// 特殊应用指令，响应为R1b
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_CMD55] <= 1'b1;
				
				c_state[WAIT_ACKR1]:
					if(time_out)	// 若长时间无响应，则初始化失败
						n_state[READ_FAILD] <= 1'b1;
					else if(ack_start) // 检测到CMD被拉低，则响应开始
						n_state[GET_RESPR1] <= 1'b1;					
					else						
						n_state[WAIT_ACKR1] <= 1'b1;				
				
				c_state[GET_RESPR1]:
					if(rx_valid & resp_fine )	// 响应正确，等待NRC周期后发送下一条命令
						n_state[WAIT_NRC2] <= 1'b1;
					else if(rx_valid & ~resp_fine) // 响应不正确，则读失败
						n_state[READ_FAILD] <= 1'b1;						
					else					
						n_state[GET_RESPR1] <= 1'b1;
				
				c_state[WAIT_NRC2]: // 上一条响应和下一条命令之间间隔NRC
					if(nrc_timeup & state_cnt==3'd0) // 若上条命令是CMD55
						n_state[SEND_ACMD6] <= 1'b1;
					else if(nrc_timeup & state_cnt==3'd1 ) // 若上条命令是ACMD6,则等待读命令
						n_state[READ_RDY] <= 1'b1;			
					else if(nrc_timeup & state_cnt==3'd2) // 若上条命令是CMD18,则等待数据
						n_state[WAIT_DATA] <= 1'b1;				
					else
						n_state[WAIT_NRC2] <= 1'b1;
												
				c_state[SEND_ACMD6]:	// 特殊应用指令，响应为R1 // 切换到宽总线模式
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_ACMD6] <= 1'b1;
										
//				c_state[SEND_CMD23]:	// 
//					if(send_over)
//						n_state[WAIT_ACKR2] <= 1'b1;
//					else
//						n_state[SEND_CMD23] <= 1'b1;				

				c_state[READ_RDY]:	// 完全准备好,随时可以读
					if(read_req)
						n_state[SEND_CMD18] <= 1'b1;
					else
						n_state[READ_RDY] <= 1'b1;
						
				c_state[SEND_CMD18]:	// 发送块读请求 
					if(send_over)
						n_state[WAIT_ACKR1] <= 1'b1;
					else
						n_state[SEND_CMD18] <= 1'b1;
						
				c_state[WAIT_DATA]:
					if(time_out)	// 若长时间无响应，则读数据
						n_state[READ_FAILD] <= 1'b1;
					else if(data_start)	// 数据开始来
						n_state[READ_DATA] <= 1'b1;						
					else					
						n_state[WAIT_DATA] <= 1'b1;
				
				c_state[READ_DATA]:
					if(read_one_block)	// 读完一个block 32个blocks 32*512B = 4*1024
						n_state[READ_WAIT] <= 1'b1;						
					else					
						n_state[READ_DATA] <= 1'b1;
						
				c_state[READ_WAIT]:
					if(read_end)	// 读完32个blocks 32*512B = 4*1024
						n_state[SEND_CMD12] <= 1'b1;						
					else if(data_start)	// 下一个block数据开始来				
						n_state[READ_DATA] <= 1'b1;
					else
						n_state[READ_WAIT] <= 1'b1;
				
				c_state[SEND_CMD12]:	// 发送RCA请求
					if(send_over)
						n_state[WAIT_ACKR1B] <= 1'b1;
					else
						n_state[SEND_CMD12] <= 1'b1;				
						
				c_state[READ_FAILD]:	// 读失败次数不满，重新开始
//					if(try_cnt)
//						n_state[SEND_CMD0] <= 1'b1;
//					else
						n_state[READ_IDLE] <= 1'b1;
						
				c_state[READ_FINISH]:	// 一次读输出完成，等待下次读
						n_state[READ_RDY] <= 1'b1;						
						
				default:
						n_state[READ_IDLE] <= 1'b1;	
			endcase
		end
	
	
	/////**************** 状态机跳转条件 *************/////

	// 发送命令,时分复用
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

	// 接收命令响应,时分复用
	
	// cmd 变低是应答开始
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
			
// 判断响应是否正确
///	reg	resp_fine; // 暂时不判
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

		
	// NRCNRC=NCC=16暂定
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
	
	// 等待SD卡响应计数器 100ms超时
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
	//	reg [2:0] nrc_state; // 1=已经发过CMD7 2=已经发过CMD12
	always @(posedge SD_clk) 
		if(rst)
			nrc_state <= 'd0;
		else if(c_state[READ_IDLE])
			nrc_state <= 'd0;			
		else if(c_state[READ_FINISH])
			nrc_state <= 3'd1;
		else if(c_state[WAIT_NRC] & nrc_timeup)			
			nrc_state <= nrc_state + 'd1;
		
	//	reg [2:0] nrc_state; // 1=已经发过CMD55 2=已经发过ACMD6 3=已经发过CMD18
	always @(posedge SD_clk) 
		if(rst)
			state_cnt <= 'd0;
		else if(c_state[READ_IDLE])
			state_cnt <= 'd0;
		else if(c_state[READ_FINISH])	 //一次读完成，回到刚发过ACMD6之后的状态	
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
					& mydata_delay1==4'hf & mydata_delay2==4'hf & mydata_delay3==4'hf) // 发送读请求后 & ~data_busy
			data_start <= 1'b1;	//
		else
			data_start <= 'b0;
			
//	reg	read_one_block; 
	always @(posedge SD_clk) 
		if(rst)
			read_one_block <= 'b0;
		else if(valid_cnt[9:0]==10'd1022) // 发送读请求后
			read_one_block <= 1'b1;	// 且数据线首次为0时
		else
			read_one_block <= 'b0;
			
//	reg	data_start;
	always @(posedge SD_clk) 
		if(rst)
			read_end <= 'b0; //读到32K次则结束
		else if(valid_cnt==20'd262143) //16kB = 32*1024次 //128KB = 128*1024 *2 = 262144 halfByte
			read_end <= 1'b1;
		else
			read_end <= 'b0;
			
	
	/////**************** 输出 *************/////
	reg	read_state; // 失败一次，即输出高电平
	always @(posedge SD_clk) 
		if(rst)
			read_state <= 1'd0;
		else if(c_state[READ_FAILD])			
			read_state <= 1'd1;
			
	reg [31:0] reg_state; // 失败一次，即输出高电平
	always @(posedge SD_clk) 
		if(rst)
			reg_state <= 'd0;
		else //if(c_state[READ_FAILD])			
			reg_state <= rx_data[39:8];
	
	reg	data_come; // 数据到来标记,发完读请求命令后
	always @(posedge SD_clk) 
		if(rst)
			data_come <= 1'd0;
		else if(c_state[SEND_CMD18] & send_over)	//	发完读请求命令后	
			data_come <= 1'd1;
		else if(c_state[SEND_CMD12])	// 读完后清零
			data_come	<= 'd0;
			
	reg	data_busy; // 开始读操作置1，读完成归零
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
