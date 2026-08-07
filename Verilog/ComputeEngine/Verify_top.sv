import falcon_pkg::*;

module Verify_top #(parameter [10:0] N = 512)(
    input logic clk,
    input logic rst_n,
    input logic start,           //Start to do Falcon verification
    input logic [63:0] axi_data,  //Input data for Input_Control
    input logic axi_valid,     //i_valid for Input Control
    input logic Sec_LV,      //0: Level I, 1: Level V
    input logic message_last,    //last message data
    input logic [9:0] message_byte_length,  //Message length (in bytes)

    output logic axi_ready,     //i_ready for Input Control
    output logic pass,   // Pass Verification
    output logic fail,   //Something went wrong, that is, return bottom
    output logic done    // Verification Finish
);

    localparam [3:0] ST_IDLE                  = 0;
    localparam [3:0] ST_HTP                   = 1;   //hash to point state
    localparam [3:0] ST_DECOMPRESS            = 2;   //decompress state
    localparam [3:0] ST_POLYMUL               = 3;   //polynomial multiplication state
    localparam [3:0] ST_POLYSUB               = 4;   //polynomial subtraction state
    localparam [3:0] ST_CHECKNORM             = 5;   //norm check state
    localparam [3:0] ST_DONE                  = 6;

    logic [3:0] state;
    logic htp_valid, decompress_valid;   //i_valid
    logic htp_ready, decompress_ready;   //i_ready
    logic input_control_done, htp_done, decompress_done, poly_accessor_done; 
    logic htp_coef_valid, htp_coef_ready, decompress_coef_valid, decompress_coef_ready;
    logic decompress_fail, checknorm_fail;
    logic [2:0] message_last_byte;
    logic [63:0] htp_message_input;
    logic [8*SIG_LEN_V-328-1:0] decompress_input;
    logic [WIDTH -1:0] htp_coef, decompress_coef;
    logic [1:0] en;
    logic [16:0] poly_addr;
    logic [63:0] w_coef, r_coef;

    
    assign message_last_byte = message_byte_length[2:0];
    assign pass = !fail;
    assign done = (state == ST_DONE);

    //For finite state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state <= ST_HTP;
                    end
                end 
                ST_HTP: begin
                    if (htp_done) begin
                        state <= ST_DECOMPRESS;
                    end
                end
                ST_DECOMPRESS: begin
                    if (decompress_done) begin
                        state <= ST_DONE;      //Temporarily set for testing
                    end
                end
                ST_DONE: begin
                    state <= ST_IDLE;
                end
                default: state <= state;
            endcase
        end
    end

    //For fail
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fail <= 'b0;
        end
        else if (state == ST_DECOMPRESS) begin
            fail <= fail || decompress_fail;
        end
        //To Do: checknorm fail
        else begin
            fail <= fail;
        end
    end

    Input_Control #(.N(N)) I_Ctrl(
        .clk(clk),
        .rst_n(rst_n),
        .state(state),  
        //0: IDLE   1: HashToPoint   2: Decompress
        .message_byte_length(message_byte_length),    //The length of message (bytes)

        .axi_data(axi_data),
        .axi_valid(axi_valid),
        .axi_ready(axi_ready),

        //Hash To Point Input Ports
        .htp_idata(htp_message_input),
        .htp_valid(htp_valid),
        .htp_ready(htp_ready),

        //Decompress Input Ports
        .decompress_idata(decompress_input),
        .decompress_valid(decompress_valid),
        .decompress_ready(decompress_ready),

        //Done
        .done(input_control_done)
    );


    HashToPoint u_htp(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .message(htp_message_input),       //r||m is input in 64-bits chunks    
        .message_valid(htp_valid),  //i_valid
        .message_last(message_last),        //Whether it is last chunk of messsage
        .message_last_bytes(message_last_byte),  //How many of last data are valid 
        .Sec_LV(Sec_LV),         //0: Level I, 1: Level V

        .coef_ready(htp_coef_ready),    //o_ready
        .message_ready(htp_ready),  //i_ready
        .coef(htp_coef),     //output coefficients
        .coef_valid(htp_coef_valid),     //o_valid
        .done(htp_done)             //The module finishes
    );


    Decompress u_decompress(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .sig_valid(decompress_valid),   //i_valid
        .sig(decompress_input),         //If security level I, {sig, (8*SIG_LEN_V-8*SIG_LEN_I)'b0}      
        // Signature: {1byte header + 40bytes nonce + signature}   Only input signature part
        .Sec_LV(Sec_LV),      //0: Level I, 1: Level V
        .coef_ready(decompress_coef_ready),  //o_ready
        
        .coef(decompress_coef),       //output coefficients
        .coef_valid(decompress_coef_valid), //o_valid
        .sig_ready(decompress_ready),   //i_ready
        .done(decompress_done),        // High if all coefficients output or fail somewhere
        .fail(decompress_fail)         // High if output bottom
    );    

    Poly_Accessor #(.N(N)) u_poly_accessor(
        .clk(clk),
        .rst_n(rst_n),
        .state(state),
        //0: IDLE   1: HashToPoint   2: Decompress
        
        //htp ports
        .htp_coef(htp_coef),
        .htp_coef_valid(htp_coef_valid),
        .htp_coef_ready(htp_coef_ready),

        //decompress ports
        .decompress_coef(decompress_coef),
        .decompress_coef_valid(decompress_coef_valid),
        .decompress_coef_ready(decompress_coef_ready),
        
        //PolyRAM ports
        .en(en), //{cen, wen}
        .w_coef(w_coef),
        .r_coef(r_coef),
        .poly_addr(poly_addr),

        .done(poly_accessor_done)
    );

    PolyRAM    u_polyram(
        .clk(clk),
        .addr(poly_addr),
        .wdata(w_coef),
        .cen(en[1]),
        .wen(en[0]),
        .rdata(r_coef)
    );
endmodule
