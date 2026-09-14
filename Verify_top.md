I/O Ports for Verify_top.sv
	input  logic                  clk,                    // clock
	input  logic                  rst_n,                   // negedge reset
	input  logic                  start,                   // start Falcon verification
	input  logic [63:0]           axi_data,                // 64-bit input control data
	input  logic                  axi_valid,               // input control data valid
	input  logic                  Sec_LV,                   // 0: Level I, 1: Level V
	input  logic                  message_last,             // last message data 
	input logic [9:0]            message_byte_length,      // message length in bytes
	output logic                  axi_ready,               // ready to accept AXI input data
	output logic                  pass,                    // verification result is pass
	output logic                  fail,                    // verification failed or something went wrong
	output logic                  done                     // verification finished

	To interact with the module:
	apply rst_n low, then release it                                   --->
	provide start high for a clock                                     --->
	send message data on axi_data and axi_valid rises                  --->
	repeat waiting for the axi_ready rises and send new values         --->
	assert message_last with the final message data beat               --->
	wait for the HashToPoint operation to finish                       --->
	wait for the HashToPoint polynomial to be stored                   --->
	send signature data on axi_data and axi_valid rises                --->
	repeat waiting for the axi_ready rises and send new values         --->
	wait for done to rise                                              

	What the module do:
	wait in ST_IDLE for start                                           --->
	enter ST_HTP and forward AXI input data to HashToPoint              --->
	consume message data when axi_valid high and axi_ready rises        --->
	wait for htp_done, then enter ST_HTP_STORE                          --->
	store the HashToPoint polynomial in PolyRAM                         --->
	wait for poly_accessor_done, then enter ST_DECOMPRESS               --->
	consume signature data  when axi_valid high and axi_ready rises     --->
	wait for decompress_done, then enter ST_DECOMPRESS_STORE            --->
	wait for poly_accessor_done, then enter ST_DONE                     --->
	assert done while ST_DONE                                           --->
	return to ST_IDLE

	Result behavior:
	fail is cleared by rst_n and becomes high when decompress_fail is high
	during ST_DECOMPRESS. Once high, fail remains high until reset.
	pass is the inverse of fail, so pass is high unless a failure is recorded. 
	(Temporarily, we haven't take checknorm into consider)

	Current implementation notes:
	ST_POLYMUL, ST_POLYSUB, and ST_CHECKNORM are declared but are not
	currently reached by the state machine. The FSM transitions directly
	from ST_DECOMPRESS_STORE to ST_DONE when poly_accessor_done is asserted.
	The checknorm_fail signal is declared but is not currently used.
 