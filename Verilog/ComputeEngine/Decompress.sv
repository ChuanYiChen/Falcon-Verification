import falcon_pkg::*;

module Decompress(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         start,        //start to do signature decompress
    input  logic                         sig_valid,   //i_valid
    input  logic [8*SIG_LEN_V-328-1:0]   sig,         //If security level I, {sig, (8*SIG_LEN_V-8*SIG_LEN_I)'b0}      
    // Signature: {1byte header + 40bytes nonce + signature}   Only input signature part
    input  logic                         Sec_LV,      //0: Level I, 1: Level V
    input  logic                         coef_ready,  //o_ready
    
    output logic [WIDTH-1:0]             coef,       //output coefficients
    output logic                         coef_valid, //o_valid
    output logic                         sig_ready,   //i_ready
    output logic                         done,        // High if all coefficients output or fail somewhere
    output logic                         fail         // High if output bottom
);

    logic [10:0] N;
    logic [10:0] idx; 

    logic [8*SIG_LEN_V-328-1:0] cs;  //current string

    logic [WIDTH-1:0] s_prime;
    logic [13:0] k;

    logic coef_fail;       //output coefficient zero with MSB 1
    logic string_fail;     //If remaining string is all zero after all coefficients generated

    localparam [1:0] ST_IDLE   = 2'd0;    //IDLE state
    localparam [1:0] ST_GENCOEF = 2'd1;   //Generate coefficients 
    localparam [1:0] ST_CHECKRS = 2'd2;   //Check remaining string all zero
    localparam [1:0] ST_DONE   = 2'd3;    //Module done

    reg [1:0] state;

    assign N = (Sec_LV)? N_V : N_I;
    assign s_prime = {7'b0, cs[62], cs[61], cs[60], cs[59], cs[58], cs[57], cs[56]};
    assign k = 14'(32'd8 * SIG_LEN_V - 32'd337 - $clog2(cs[8*SIG_LEN_V-328-1:8]));
    assign coef = (cs[63])? -(s_prime + (k << 7)) : s_prime + (k << 7);
    assign coef_fail = (coef == 'b0) && (cs[63] == 1);
    assign string_fail = (cs != 'b0);
    assign coef_valid = (state == ST_GENCOEF) && (idx < N);
    assign done = (state == ST_DONE);
    assign sig_ready = (state == ST_IDLE);

    //For FSM
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state <= ST_IDLE;
        end
        else if (state == ST_IDLE && sig_valid) begin
            state <= ST_GENCOEF;
        end
        else if (state == ST_GENCOEF && idx >= N) begin
            state <= ST_CHECKRS;            
        end
        else if (state == ST_CHECKRS) begin
            state <= ST_DONE;
        end
        else if (state == ST_DONE) begin
            state <= ST_IDLE;
        end
        else begin
            state <= state;
        end
    end

    //For the idx
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            idx <= 'b0;
        end
        else if (start) begin
            idx <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE : begin
                    idx <= 'b0; 
                end 
                ST_GENCOEF: begin
                    idx <= idx + 11'b1; 
                end
                ST_DONE: begin
                    idx <= 'b0;
                end
                default: idx <= idx;
            endcase
        end
    end

    //For the fail, once failed, fail until all coefficients output
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            fail <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    fail <= 'b0;
                end
                ST_GENCOEF: begin
                    fail <= fail || coef_fail; 
                end
                ST_CHECKRS: begin
                    fail <= fail || string_fail;
                end
                ST_DONE: begin
                    fail <= 'b0;
                end
                default: fail  <= fail;
            endcase
        end
    end
    
    //For the string 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= 'b0;
        end
        else if (start) begin
            cs <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if (sig_valid) begin
                        cs <= sig;
                    end
                end
                ST_GENCOEF: begin
                    if (coef_valid && coef_ready) begin
                       cs <= cs << (9 + k); 
                    end
                end
                ST_DONE: begin
                    cs <= 'b0;
                end 
                default: cs <= cs;
            endcase
        end
    end  
endmodule
