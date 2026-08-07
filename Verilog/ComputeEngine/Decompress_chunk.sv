import falcon_pkg::*;

module Decompress_chunk(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         sig_valid,
    input  logic [32-1:0]                sig,        
    input  logic                         Sec_LV,      //0: Level I, 1: Level V
    
    output logic [WIDTH-1:0]             coef,
    output logic                         coef_valid,
    output logic                         sig_ready,   //i_ready 
    output logic                         done,        // High if all coefficients output or fail somewhere
    output logic                         fail         // High if output bottom
);

    logic [10:0] N;
    logic [10:0] idx; 

    logic [63:0] cs;  //current string

    logic [WIDTH-1:0] s_prime;
    logic [13:0] k;
    logic [10:0] sbytelen;
    logic coef_fail;
    logic string_fail;
    logic [6:0] valid_buffer; //Only buffer[63:valid_buffer] are valid
    logic success_genk;

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_CONSUME = 3'd1;
    localparam [2:0] ST_GENK    = 3'd2;
    localparam [2:0] ST_GENCOEF = 3'd3;   //Generate coefficients 
    localparam [2:0] ST_CHECKRS = 3'd4;   //Check remaining string all zero
    localparam [2:0] ST_DONE    = 3'd5;

    reg [2:0] state;

    reg [63:0] buffer;
    reg [13:0] input_counter;

    assign N = (Sec_LV)? N_V : N_I;
    assign sbytelen = (Sec_LV)? SIG_LEN_V : SIG_LEN_I;
    assign slen = 8*sbytelen - 14'd328;
    assign s_prime = {7'b0, buffer[62], buffer[61], buffer[60], buffer[59], buffer[58], buffer[57], buffer[56]};
    assign success_genk = !(buffer[55:0] == 'b0);
    assign coef = (buffer[63])? -(s_prime + (k << 7)) : (s_prime + (k << 7));
    assign coef_fail = (coef == 'b0) && (buffer[63] == 1);
    assign string_fail = (buffer != 'b0);
    assign coef_valid = (state == ST_GENCOEF) && (idx < N);
    assign done = (state == ST_DONE);
    assign sig_ready = (state == ST_IDLE) || ;

    //For FSM
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state <= ST_IDLE;
        end
        else if (state == ST_IDLE && sig_valid) begin
            state <= ST_GENK;
        end
        else if (state == ST_CONSUME && sig_valid) begin
            state <= ST_GENK;
        end
        else if (state == ST_GENK) begin
            if (buffer[55:0] == 56'b0) begin
                state <= ST_CONSUME;
            end
            else begin
                state <= GENCOEF;
            end
        end
        else if (state == ST_GENCOEF) begin
            if (idx >= N) begin
                state <= ST_CHECKRS; 
            end
            else begin
                state <= ST_GENK;
            end        
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

    //For valid_buffer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_buffer <= 7'd64;
        end
        else begin
            case (state)
                ST_IDLE : begin
                    if (sig_valid) begin
                        valid_buffer <= valid_buffer - 7'd32;
                    end
                end
                ST_CONSUME: begin
                    if (sig_valid && input_counter < 8 * sbytelen - 360) begin
                        valid_buffer <= valid_buffer - 7'd32;
                    end
                    else if (sig_valid && input_counter >= 8 * sbytelen - 14'd360) begin
                        valid_buffer <= valid_buffer + (8 * sbytelen - 14'd328 - input_counter)[6:0];
                    end
                end
                ST_GENK: begin
                    if (!success_genk) begin
                        valid_buffer <= 7'd64;
                    end
                    else begin
                        valid_buffer <= 7'd64 - $clog2(buffer[54:0]) + valid_buffer;
                    end
                end
                default: valid_buffer <= valid_buffer;
            endcase
        end
    end

    //For input counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_counter <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                   if (sig_valid) begin
                    input_counter <= input_counter + 14'd32;
                   end
                end
                ST_GENCOEF: begin
                    if (sig_valid && (input_counter < 8 * sbytelen - 14'd360)) begin
                        input_counter <= input_counter + 14'd32;
                    end
                    else begin
                        if (sig_valid) begin
                            input_counter <= 8 * sbytelen - 14'd328;
                        end
                        else begin
                            input_counter <= input_counter;
                        end
                    end
                end
                ST_DONE: begin
                    input_counter <= 'b0;
                end
                default: input_counter <= input_counter;
            endcase
        end
    end
    
    //For the buffer management 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if(sig_valid) begin
                        buffer <= {sig, 32'b0};
                    end
                end
                ST_CONSUME: begin
                    buffer <= (buffer << (9 + $clog2(buffer[54:0]) - valid_buffer)) || (sig >> (9 + $clog2(buffer[54:0]) - valid_buffer));
                end 
                default: buffer <= buffer;
            endcase
        end
    end

    //For the idx
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
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

    //For 
endmodule