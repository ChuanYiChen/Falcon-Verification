import falcon_pkg::*;

module Input_Control #(
   parameter [10:0] N = 512
) (
    input   logic                        clk,
    input   logic                        rst_n,
    input   logic [3:0]                  state,  
    //0: IDLE   1: HashToPoint   2: Decompress
    input   logic [9:0]                  message_byte_length,    //The length of message (bytes)

    input   logic [63:0]                 axi_data,
    input   logic                        axi_valid,
    output  logic                        axi_ready,

    //Hash To Point Input Ports
    output  logic [63:0]                 htp_idata,
    output  logic                        htp_valid,
    input   logic                        htp_ready, 

    //Decompress Input Ports
    output  logic [63:0]                 decompress_idata,
    output  logic                        decompress_valid,
    input   logic                        decompress_ready,

    //Done
    output  logic                        done
);
 
    logic [9:0] i_counter;
    //Signature 666/1280 bytes, Message 0~1023 bytes, Public Key 897/1793 bytes
    //I   0~83: Signature  84~84+MBL/8 : Message       85+MBL/197~MBL/8 : pk
    //V   0~159: Signature 160~160+MBL/8 : Message     161+MBL/8~385+MBL/8 : pk
    logic [9:0] sig_first, sig_last, msg_first, msg_last, pk_first, pk_last;

    //The first and last chunk of sig/msg/pk
    assign sig_first = 10'd5;
    assign sig_last = (N == 512)? 10'd83 : 10'd159;
    assign msg_first = (N == 512)? 10'd84 : 10'd160;
    assign msg_last = (N == 512)? (10'd84 + (message_byte_length >> 3)) : (10'd160 + (message_byte_length >> 3));
    assign pk_first = (N == 512)? (10'd85 + (message_byte_length >> 3)) : (10'd161 + (message_byte_length >> 3));
    assign pk_last = (N == 512)? (10'd197 + (message_byte_length >> 3)) : (10'd385 + (message_byte_length >> 3));



    assign htp_valid = axi_valid && (((10'd4 >= i_counter)) || ((i_counter >= msg_first) && (msg_last >= i_counter)));
    assign decompress_valid = axi_valid && (i_counter >= sig_last);

    //For i_counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_counter <= 'b0;
        end
        else if (state == 4'd0) begin
            i_counter <= 'b0;
        end
        else begin
            if (axi_valid && axi_ready) begin
                i_counter <= i_counter + 10'b1;
            end
        end
    end
   
    //For axi_ready
    always_comb begin
        axi_ready = 1'b1;
        if (htp_valid) begin
            axi_ready = htp_ready;
        end
        else if ((state == 4'd1) || (state == 4'd2)) begin
            axi_ready = (i_counter >= sig_last) ? decompress_ready : 1'b1;
        end
    end

    assign htp_idata = axi_data;
    assign decompress_idata = axi_data;

    assign done = (state == 4'd1 && htp_valid && htp_ready) || 
                  (state == 4'd2 && decompress_valid && decompress_ready);
endmodule
