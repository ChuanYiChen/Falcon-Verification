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
    localparam [3:0] ST_POLYMUL_I             = 3;   //polynomial multiplication consume state
    localparam [3:0] ST_POLYMUL_O             = 4;   //polynomial multiplication output state
    localparam [3:0] ST_POLYSUB               = 5;   //polynomial subtraction state
    localparam [3:0] ST_CHECKNORM             = 6;   //norm check state
    localparam [3:0] ST_DONE                  = 7;

    logic [3:0] state;
    logic htp_valid, decompress_valid, pk_valid;   //i_valid
    logic htp_ready, decompress_ready, pk_ready;   //i_ready
    logic input_control_done, htp_done, decompress_done, polymul_done, poly_accessor_done; 
    logic htp_coef_valid, htp_coef_ready, decompress_coef_valid, decompress_coef_ready, c_coef_valid, s_2h_coef_valid, s1_coef_valid;
    logic pmi_coef_valid, pmi_coef_ready, pmo_coef_valid, pmo_coef_ready, sub_ready, s1_coef_ready;
    logic decompress_fail, checknorm_fail;
    logic [2:0] message_last_byte;
    logic [63:0] htp_message_input;
    logic [8*SIG_LEN_V-328-1:0] decompress_input;
    logic [N*WIDTH-1:0] pk, pmi, pmo;
    logic [WIDTH -1:0] htp_coef, decompress_coef, pmi_coef, pmo_coef, c_coef, s_2h_coef, s1_coef;
    logic [1:0] enA, enB, enC;
    logic [16:0] poly_addrA, poly_addrB, poly_addrC;
    logic [63:0] w_coefA, w_coefB, w_coefC, r_coefA, r_coefB, r_coefC;

    
    assign pk_ready = (state == ST_POLYMUL_I);
    assign pmi_coef_ready = (state == ST_POLYMUL_I);
    assign pmo_coef_valid = (state == ST_POLYMUL_O);
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
                        state <= ST_POLYMUL_I;      //Temporarily set for testing
                    end
                end
                ST_POLYMUL_I: begin
                    if (polymul_done) begin
                        state <= ST_POLYMUL_O;
                    end
                end
                ST_POLYMUL_O: begin
                    if (poly_accessor_done) begin
                        state <= ST_POLYSUB;
                    end
                end
                ST_POLYSUB: begin
                    if (poly_accessor_done) begin
                        state <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    state <= ST_IDLE;
                end
                default: state <= state;
            endcase
        end
    end

    //for pmi
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pmi <= 'b0;
        end
        else if (state == ST_IDLE) begin
            pmi <= 'b0;
        end
        else if (state == ST_POLYMUL_I && pmi_coef_valid && pmi_coef_ready) begin
            pmi <= {pmi[N*WIDTH-15:0], pmi_coef};
        end
        else begin
            pmi <= pmi;
        end
    end

    //for pmo_coef
    assign pmo_coef = pmo[ ((32'(N) - 32'({1'b0, poly_addrA[9:0]})) * WIDTH - 14) +: 14 ];

    //For fail
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fail <= 'b0;
        end
        if (state == ST_IDLE) begin
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

        //PolyMul Input Ports   Public Key
        .pk(pk),
        .pk_valid(pk_valid),
        .pk_ready(pk_ready),

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
    
    PolyMul #(.N({21'b0, N})) u_polymul(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a_in(pmi),
        .b_in(pk),
        .prod_out(pmo),
        .done(polymul_done)
    );

    Addq u_addq(
        .clk(clk),
        .rst_n(rst_n),

        .i_valid(c_coef_valid && s_2h_coef_valid),
        .o_ready(s1_coef_ready),
        .i_ready(sub_ready),
        .o_valid(s1_coef_valid),

        .din1(c_coef),              //c
        .din2(s_2h_coef),              //s_2h
        .dout(s1_coef),       //s_1

        .sub(1'b1)   // 0:Add, 1:Sub
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

        //PolyMul input ports  ........  Decompressed polynomial
        .pmi_coef(pmi_coef),
        .pmi_coef_valid(pmi_coef_valid),
        .pmi_coef_ready(pmi_coef_ready),

        //PolyMul output ports
        .pmo_coef(pmo_coef),
        .pmo_coef_valid(pmo_coef_valid),
        .pmo_coef_ready(pmo_coef_ready),

        //PolySub input ports
        .c_coef(c_coef),
        .c_coef_valid(c_coef_valid),
        .c_coef_ready(sub_ready),

        .s_2h_coef(s_2h_coef),
        .s_2h_coef_valid(s_2h_coef_valid),
        .s_2h_coef_ready(sub_ready),

        //PolySub output ports
        .s1_coef(s1_coef),
        .s1_coef_valid(s1_coef_valid),
        .s1_coef_ready(s1_coef_ready),
        
        //PolyRAM portsA
        .enA(enA), //{cen, wen}
        .w_coefA(w_coefA),
        .r_coefA(r_coefA),
        .poly_addrA(poly_addrA),

        //PolyRAM portsB
        .enB(enB), //{cen, wen}
        .w_coefB(w_coefB),
        .r_coefB(r_coefB),
        .poly_addrB(poly_addrB),

         //PolyRAM portsC
        .enC(enC), //{cen, wen}
        .w_coefC(w_coefC),
        .r_coefC(r_coefC),
        .poly_addrC(poly_addrC),

        .done(poly_accessor_done)
    );

    PolyRAM    u_polyram(
        .clk(clk),
        .addrA(poly_addrA),
        .wdataA(w_coefA),
        .cenA(enA[1]),
        .wenA(enA[0]),
        .rdataA(r_coefA),
        .addrB(poly_addrB),
        .wdataB(w_coefB),
        .cenB(enB[1]),
        .wenB(enB[0]),
        .rdataB(r_coefB),
        .addrC(poly_addrC),
        .wdataC(w_coefC),
        .cenC(enC[1]),
        .wenC(enC[0]),
        .rdataC(r_coefC)
    );

endmodule
