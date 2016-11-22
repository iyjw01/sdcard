`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Create Date:    14:47:34 05/16/2014 
// Module Name:    SD_TOP 
// Description: 	TOP procedure, 
// Revision: 		update info: 1 xc7a100t -1 fgg484	check
//										 2 change dcm_clk input 50MHz to 100MHz PLL	check
//							          3 buffer from 16k to 128K(sd_read datainpro)
//										 4 ucf update
//										 5 SD_CLK output directly
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////
`define DEBUG_PIN
//`define SD1TEST
//`define UseLinuxCommand

module SD_TOP(
		 FPGACLK,				//main clock in = 50M
		//SD interface
//		 SD1,
//		 SD1_CLK,
//		 SD1_CMD,
//		 SD1_OE, 
		 SD2,
		 SD2_CLK,//
		 SD2_CMD, //
//		 SD2_OE, //
		// USB interface
//		USB1,
//		USB1_CMD,
//		USB1_CLK,
		USB2,
		USB2_CMD,
		USB2_CLK,
		
		//Micro Controller interface
		 I2CSCK,				//this one will replace STROBE for test
		 TX_232,
		 RX_232,
		//IO Control from Micro-controller
		 REV3,REV4,
		//Carrage board interface
		 STROBE,RESET,DIR,
		 PIXEL,
		 CH,
		 CHw,
		 IRC_Y1,IRC_Y2,IRC_Y4,
		 ENA		
);


		input FPGACLK;				//main clock in = 50M
		//SD interface
//		input [3:0] SD1;
		input [3:0] SD2;
		output SD2_CLK;//SD1_CLK,
		inout  SD2_CMD; //SD1_CMD,
//		output SD2_OE; //SD1_OE, 
//		
//		input	[3:0] USB1;
//		input 	USB1_CMD;
//		input 	USB1_CLK;
		input	[3:0] USB2;
		input 	USB2_CMD;
		input 	USB2_CLK;
		
		//Micro Controller interface
		output I2CSCK;				//this one will replace STROBE for test
		output TX_232;
		input RX_232;
		//IO Control from Micro-controller
		input REV3,REV4;
		//Carrage board interface
		output STROBE,RESET,DIR;
		output PIXEL;
		output [16:1] CH;
		output [16:1] CHw;
		input IRC_Y1,IRC_Y2,IRC_Y4;
		output ENA;	
		

PULLUP CMD2pullup(.O(SD2_CMD));		//SD needs pull up?
assign STROBE = 1'b0;					//STROBE is replaced by I2CSCK, due to hardware error

wire rst;

//SD start action select
wire WhichSD = 1'b1;		//SD selection -- 0 = SD1, 1=SD2. SD2 will be selected for test purpose
wire ExternTrig = REV3;

wire ReadSDTrig;	//Trig signal to read SD, from DataInPro Module
wire SD2ReadTrig = ReadSDTrig & WhichSD;
wire SD1ReadTrig = ReadSDTrig & !WhichSD;

assign	SD2_OE = WhichSD;
//assign	SD1_OE = ~WhichSD;


	wire	clk_50m;
	wire	clk_6m25;
	wire	locked;
  clk_div dcm_clk
		(// Clock in ports
		 .CLK_IN1(FPGACLK),      // IN
		 // Clock out ports
		 .CLK_OUT1(clk_50m),     // OUT
		 .CLK_OUT2(clk_6m25),     // OUT
		 // Status and control signals
		 .RESET(1'b0),// IN
		 .LOCKED(locked));      // OUT
	 
assign rst =  ~locked; //REV4 | 


/*********************************************
SD CLK,CMD interface
*********************************************/
//SD CMD switch between init and reading

/* synthesis syn_keep = 1 */		wire sd2_cmd_resp;

wire SD2_clk_init; 	// Clock for SD init
wire SD2_cmd_en;  	// CMD enable during init
wire SD2_cmd_o; 		// CMD output during init
wire init2_o;			// init finished
wire SD2_cmd_enr;	   // SD CMD out enable
wire SD2_cmdr_o;		// SD CMD output

reg sd2_cmd_oe_o;
reg sd2_cmd_out_o = 1'b0;

always @(*) begin
	if(!init2_o)	begin
			sd2_cmd_oe_o<=SD2_cmd_en;
			sd2_cmd_out_o<=SD2_cmd_o;
	end
	else begin
			sd2_cmd_oe_o<=SD2_cmd_enr;
			sd2_cmd_out_o<=SD2_cmdr_o;
	end
end

//IOBUF iobufsd2cmd(.I(sd2_cmd_out_o),.O(sd2_cmd_resp),.IO(SD2_CMD),.T(!(WhichSD & sd2_cmd_oe_o)));


// USE REV4 to switch between USB and inside interface
wire [3:0] sd2_in;
assign 	 sd2_in = REV4?USB2:SD2;

wire SD2_CLK;
assign SD2_CLK = REV4?USB2_CLK:clk_6m25;

wire  sd2_cmd_out_oo ;
assign sd2_cmd_out_oo= REV4?USB2_CMD:sd2_cmd_out_o;

IOBUF iobufsd2cmd(.I(sd2_cmd_out_oo),.O(sd2_cmd_resp),.IO(SD2_CMD),.T(!(WhichSD & sd2_cmd_oe_o)));

//	ODDR2 #(
//      .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1" 
//      .INIT(1'b0),    // Sets initial state of the Q output to 1'b0 or 1'b1
//      .SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
//   ) ODDR2_inst (
//      .Q(SD2_CLK),   // 1-bit DDR output data
//      .C0(clk_6m25),   // 1-bit clock input
//      .C1(~clk_6m25),   // 1-bit clock input
//      .CE(1'b1), // 1-bit clock enable input
//      .D0(1'b1), // 1-bit data input (associated with C0)
//      .D1(1'b0), // 1-bit data input (associated with C1)
//      .R(1'b0),   // 1-bit reset input
//      .S(1'b1)    // 1-bit set input
//   );
	
/***********************************
SD Card init instance
**************************************/
wire [126:0] reg_cid2; // CID register
wire [31:0] reg_ocr2; // OCR register
wire [15:0] reg_sta2; // card status
wire [15:0] reg_rca2; // RCA address
		
SD_initial SD2_initial_inst (
    .rst(rst), 
    .SD_clk(clk_6m25), 
    .SD_clk_init(SD2_clk_init), 
    .SD_trig(ExternTrig), 
    .SD_cmd_en(SD2_cmd_en), 
    .SD_cmd(SD2_cmd_o), 
    .SD_cmd_resp(sd2_cmd_resp),
	 .init_o(init2_o),
    .reg_cid(reg_cid2), 
    .reg_ocr(reg_ocr2), 
    .reg_sta(reg_sta2), 
    .reg_rca(reg_rca2)
    );
	 

/*********************************************
SD Reading instance 
*************************************/
		wire [31:0] read_sec;
		wire read_state2; 	// SD reading status,to see if SD reading success or not
		wire [31:0] reg_state;
		
		wire [3:0]mydata2_o; 
		wire myvalid2_o;
		wire data2_come; 
		wire data2_busy;
		
SD_read SD2_read_inst (
    .rst(rst), 
    .SD_clk(clk_6m25), 
    .init_i(init2_o), 
    .reg_rca(reg_rca2), 
    .SD_cmd_en(SD2_cmd_enr), 
    .SD_cmd(SD2_cmdr_o), 
    .SD_cmd_resp(sd2_cmd_resp), 
    .sec(read_sec), 
    .read_req(TrigReadStart), //SD2ReadTrig
    .data0_in(sd2_in[0]), //SD2[0]
    .data1_in(sd2_in[1]), //SD2[1]
    .data2_in(sd2_in[2]), //SD2[2]
    .data3_in(sd2_in[3]), //SD2[3]
    .read_state(read_state2), 
	 .reg_state(reg_state),
    .mydata_o(mydata2_o), 
    .myvalid_o(myvalid2_o), 
    .data_come(data2_come), 
    .data_busy(data2_busy)
    );
	 

/********************************************
Uart instance
*************************************************/
wire UARTCLK;
wire [7:0]TxData;
wire [7:0]RxData;
//reg StartTx;
wire RxGot;
wire TxIdle;
clkdiv clkdiv(.clk(clk_50m), .clkout(UARTCLK));
uarttx uarttx(.clk(UARTCLK), .datain(TxData), .wrsig(StartTx), .idle(TxIdle), .tx(TX_232));
uartrx uartrx(.clk(UARTCLK), .rx(RX_232), .dataout(RxData), .rdsig(RxGot), .datagot(datagot),.dataerror(), .frameerror());

wire rstin = rst ;//| !init2_o;		//for SD2 test only
/*********************************************
Data sync process instance
************************************************/
wire [31:0] StartAddr;
wire [31:0] MaxBlocks;
wire data_clkout;
SyncCtrl SyncCtrl(.Ctl_clk(clk_6m25),
//						.uartclk(UARTCLK),
						.rst(rst),
						.startbutton(ExternTrig),
						.ReadOutFlag(ReadOutFlag),
						.StartPrinting(StartPrinting),
						.RxData(RxData),
						.TxData(TxData),
						.TxIdle(TxIdle),
						.RxGot(RxGot),
						.UartData_ACK(datagot),
						.StartTx(StartTx),
						.ReadingFinished(ReadingFinished),
						.SD_sec(StartAddr),
						.WhichSD(),  //WhichSD
						.ReadingStart(ReadingStart),	
						.MaxBlocks(MaxBlocks),
						.StartPulse(StartPulse),
						.CMYKOutEn(CMYKOutEn),
						.STROBE(I2CSCK),
//						.STROBE(data_clkout),		//maybe no need, see ODDR2 below
						.RESET(RESETHead),
						.DIR(DIR),
						.PIXEL(PixelReal),
						.CH(CH),		//.CHw(CHw),
						.IRC_Y1(IRC_Y1),
						.IRC_Y2(IRC_Y2),
						.IRC_Y4(IRC_Y4),
						.ENA(ENA),
						.data_C(data_C),
						.data_M(data_M),
						.data_Y(data_Y),
						.data_K(data_K),
						.PeriodReadingFinish(PeriodReadingFinish)
//	.debug0(debug0),.debug1(debug1),.debug2(debug2),.debug3(debug3),.debug4(debug4),.debug5(debug5)
);

/************************************************
SD Data in-to buffer process instance
************************************************/
reg [599:0] init_delay;
always @(posedge clk_6m25)
	init_delay <= {init_delay[598:0],init2_o};


wire [31:0] MaxBlocks_test = 32'hffff;
wire [31:0] StartAddr_test = 32'h0;

wire [7:0] FIFODataOut0;
wire [7:0] FIFODataOut1;
wire [7:0] FIFODataOut2;
wire [7:0] FIFODataOut3;
//FIFORdEn0/1 = Enable read FIFO0/1,and reading clock is FIFORdClk
wire FIFORdEn0 = FIFORd0;
wire FIFORdEn1 = FIFORd1;
wire FIFORdClk = fifoCLK_R;	
DataInPro DataInPro (
    .rst(rst), 
    .clkin(clk_6m25), 
    .ReadingStart(init_delay[521]), //ReadingStart init_delay[520] & ~
    .MaxBlocks(MaxBlocks_test), //MaxBlocks
    .SDAddrStart(StartAddr_test), 
    .TrigReadStart(TrigReadStart), 
    .SDAddr(read_sec), 
    .ReadingFinished(ReadingFinished), 
    .DataValid(myvalid2_o), // SD output
    .SDDataIn(mydata2_o), 
    .data_busy(data2_busy), 
    .FIFO_Rd1(FIFORd0), 	
    .FIFO_Rd2(FIFORd1), 
	 .FIFORdClk(FIFORdClk),
    .ReadLenth(8'd64), 
    .FIFODataOut0(FIFODataOut0), 
    .FIFODataOut1(FIFODataOut1), 
    .FIFODataOut2(FIFODataOut2), 
    .FIFODataOut3(FIFODataOut3),
	 .FIFO_OUTCLK(FIFO_OUTCLK),
    .StartPulse(StartPulse)
    );
//	 

/***************************************************
Buffer data output process instance
***********************************************/
//reg [255:0] FIFODataOut0;
DataOutPro DataOutPro(
	.rst(rst),
	.clkin(clk_6m25),
	.DataOutStart(ReadOutFlag),					//Start/trig one cycle data output from buffers
	.StartPrinting(StartPrinting),				//Enable signal for data out (all periods)
	.data_C(data_C),.data_M(data_M),.data_Y(data_Y),.data_K(data_K),	//4 channel data output
	.PeriodReadingFinish(PeriodReadingFinish),//one cycle data output finished
	.CMYKOutEn(CMYKOutEn),							//data output enable (in one period)
	 .FIFO_OUTCLK(FIFO_OUTCLK),
	.FIFODataOut0(FIFODataOut0),.FIFODataOut1(FIFODataOut1),.FIFODataOut2(FIFODataOut2),.FIFODataOut3(FIFODataOut3),
//	.FIFODataOut4(FIFODataOut4),.FIFODataOut5(FIFODataOut5),.FIFODataOut6(FIFODataOut6),.FIFODataOut7(FIFODataOut7),
	.FIFORdEn0(FIFORd0),.FIFORdEn1(FIFORd1),		//FIFO Reading enable
	.testpulse(TestPulse),
	.fifoCLK_R(fifoCLK_R)							//FIFO clocks
    );
	 





////  ports for test
assign CHw[1] = |{reg_cid2,reg_ocr2,reg_sta2,reg_rca2,mydata2_o,myvalid2_o,rst,reg_state,
						FIFODataOut0,FIFODataOut1,FIFODataOut2,FIFODataOut3,FIFORd0,TestPulse,/*FIFORd1,*/fifoCLK_R,FIFO_OUTCLK};

/****************************************************
pin signals output for logical analyzer
*****************************************************/
`ifdef UseLinuxCommand
assign RESET = RESETHead;
`else
assign RESET = !ExternTrig;
`endif

`ifdef SD1TEST
//CHw for output monitoring for test purpose
assign CHw[8:1] = 8'h00;
`ifdef DEBUG_PIN
//OBUF pixelo(.O(PIXEL),.I(!WhichSD && SD1_CLK_pad));	//for debug monitoring, note that PIXEL pin ...???
//OBUF pixelo(.O(PIXEL),.I(SD1Start && SD1_CLK_pad));	//for debug monitoring, note that PIXEL pin ...???
OBUF ch1buf(.O(CHw[9]),.I(1'b1));//clkSD;

//assign CHw[10] = 0;//init2_o;
//assign CHw[11] = SD1[3];
//assign CHw[12] = SD1[2];
//
//assign CHw[14] = SD1[0];
//assign CHw[15] = SD1_CMD;

OBUF ch8buf(.O(CHw[16]),.I(sd1_init_cmd_en));/////not monitorred---------------------------
//
assign CHw[13] = SD1[1];

`endif

`else
//CHw for output monitoring for test purpose
assign CHw[8:2] = 8'h00;


`ifdef DEBUG_PIN
//OBUF pixelo(.O(PIXEL),.I(testclocken && SD2_CLK_pad));	//for debug monitoring, note that PIXEL pin ...???
OBUF pixelo(.O(PIXEL),.I(ExternTrig));//CLKDV));	//for debug monitoring, note that PIXEL pin ...???
//OBUF pixelo(.O(PIXEL),.I(testclocken && clkSD));	//for debug monitoring, note that PIXEL pin ...???
//OBUF pixelo(.O(PIXEL),.I(SD2Start && SD2_CLK_pad));	//for debug monitoring, note that PIXEL pin ...???
OBUF ch1buf(.O(CHw[9]),.I(1'b1));//clkSD;
assign CHw[10] = myvalid2_o;//SD2Start;//debug0;//init2_o;
assign CHw[11] = mydata2_o[0];//debug1;//SD2_CMD_IN;////SD2[3];
assign CHw[12] = mydata2_o[1];//debug2;//sd2_cmd_r_en;//SD2_2;//debug2;//;//SD2[2];
assign CHw[14] = mydata2_o[2];//debug3;////sd2_cmd_out_o;//SD2_3;
assign CHw[15] = mydata2_o[3];//debug4;//myvalid2_o;//;//sd2_cmd_out_o;
assign CHw[16] = sd2_cmd_resp;//mydata2_o[0];//sd2_cmd_out_o;//SD2_CMD_IN;//SD2Start;//SD2[1];//SD2Start;
//OBUF ch8buf(.O(CHw[16]),.I(sd2_init_cmd_en));/////not monitorred---------------------------
//
assign CHw[13] = 1'b0;//SD2[1];
`else
assign CHw[16:9] = 8'h00;
assign PIXEL = PixelReal;
`endif


`endif
endmodule
