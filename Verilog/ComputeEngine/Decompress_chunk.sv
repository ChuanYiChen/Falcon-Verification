import falcon_pkg::*;

module Decompress_chunk(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         start,
    input  logic                         sig_valid,
    input  logic                         coef_ready,
    input  logic [63:0]                  sig,        
    input  logic                         Sec_LV,      //0: Level I, 1: Level V
    
    output logic [WIDTH-1:0]             coef,
    output logic                         coef_valid,
    output logic                         sig_ready,   //i_ready 
    output logic                         done,        // High if all coefficients output or fail somewhere
    output logic                         fail         // High if output bottom
);

    logic [10:0] N;
    logic [10:0] idx; 

    logic [127:0] buffer;  //current string

    logic [WIDTH-1:0] s_prime;
    logic [13:0] k;
    logic       neg;
    logic coef_fail;
    logic success_genk;
    logic string_fail;
    logic need_consume;
    logic [7:0] valid_buffer;   //buffer[127:valid_buffer] are meaningful bits

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_CONSUME = 3'd1;
    localparam [2:0] ST_GENS    = 3'd2;
    localparam [2:0] ST_GENK    = 3'd3;
    localparam [2:0] ST_GENCOEF = 3'd4;   //Generate coefficients 
    localparam [2:0] ST_CHECKRS = 3'd5;   //Check remaining string all zero
    localparam [2:0] ST_DONE    = 3'd6;

    logic [2:0] state;
    logic [2:0] next_state;

    assign N = (Sec_LV)? N_V : N_I;
    assign need_consume = valid_buffer > 8'd120;
    assign coef_fail = (coef == 'b0) && (buffer[127] == 1);
    assign string_fail = (buffer != 'b0);

    assign coef_valid = (state == ST_GENCOEF) && (idx < N);
    assign done = (state == ST_DONE);
    assign sig_ready = (state == ST_IDLE) || (state == ST_CONSUME);


    //For FSM
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state <= ST_IDLE;
            next_state <= ST_IDLE;
        end
        else if (start) begin
            state <= ST_IDLE;
            next_state <= ST_IDLE;
        end
        else if (state == ST_IDLE && sig_valid) begin
            state <= ST_GENS;
        end
        else if (state == ST_CONSUME && sig_valid) begin
            state <= next_state;
        end
        else if (state == ST_GENS) begin
            if (need_consume) begin
                state <= ST_CONSUME;
                next_state <= ST_GENK;
            end
            else begin
                state <= ST_GENK;
            end
        end
        else if (state == ST_GENK) begin
            if (success_genk) begin
                state <= ST_GENCOEF;
            end
            else if (need_consume) begin
                state <= ST_CONSUME;
                next_state <= ST_GENK;
            end
            else begin
                state <= ST_GENK;
            end
        end
        else if (state == ST_GENCOEF) begin
            if (coef_valid && coef_ready) begin
                if (idx >= N) begin
                    state <= ST_CHECKRS; 
                end
                else begin
                    state <= ST_GENS;
                end
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
            next_state <= next_state;
        end
    end
    
    //For neg and s_prime
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neg    <= 'b0;
            s_prime <= 'b0;
        end
        else if (start) begin
            neg    <= 'b0;
            s_prime <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    neg    <= 'b0;
                    s_prime <= 'b0;
                end
                ST_GENS: begin
                    neg     <= buffer[127];
                    s_prime <= {7'b0, buffer[126], buffer[125], buffer[124], buffer[123], buffer[122], buffer[121], buffer[120]};;
                end
                ST_GENCOEF: begin
                    if (coef_valid && coef_ready) begin
                        neg    <= 'b0;
                        s_prime <= 'b0;
                    end
                end
                default: begin
                    neg <= neg;
                    s_prime <= s_prime;
                end
            endcase
        end
    end

    //For k, success_genk
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k <= 'b0;
            success_genk <= 'b0;
        end
        else if (start) begin
            k <= 'b0;
            success_genk <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin 
                    k <= 'b0;
                    success_genk <= 'b0;
                end
                ST_GENS: begin
                    k <= 'b0;
                    success_genk <= 'b0;
                end
                ST_GENK: begin
                    if (buffer == 128'b0) begin
                        k <= k + 14'd128 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127:64] == 64'b0) begin
                        k <= k + 14'd64 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127:96] == 32'b0) begin
                        k <= k + 14'd32 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127:112] == 16'b0) begin
                        k <= k + 14'd16 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127:120] == 8'b0) begin
                        k <= k + 14'd8 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127:124] == 4'b0) begin
                        k <= k + 14'd4 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127:126] == 2'b0) begin
                        k <= k + 14'd2 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else if (buffer[127] == 1'b0) begin
                        k <= k + 14'd1 - {6'b0, valid_buffer};
                        success_genk <= 'b0;
                    end
                    else begin
                        k <= k;
                        success_genk <= 'b1;
                    end
                end
                default: begin 
                    k <= k;
                    success_genk <= success_genk;
                end
            endcase
        end
    end

    //For coef
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coef <= 'b0;
        end
        else if (start) begin
            coef <= 'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    coef <= 'b0;
                end 
                ST_GENCOEF: begin
                    if (neg) begin
                        coef <= -(s_prime + (k << 7));
                    end
                    else begin
                        coef <= s_prime + (k << 7);
                    end
                end
                default:  coef <= coef;
            endcase
        end
    end

    //For buffer and valid_buffer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer <= 128'b0;
            valid_buffer <= 8'd128;
        end
        else if (start) begin
            buffer <= 128'b0;
            valid_buffer <= 8'd128;
        end
        else begin
            case (state)
                ST_IDLE : begin
                    if (sig_valid) begin
                        buffer <= {sig, 64'b0};
                        valid_buffer <= valid_buffer - 8'd64;
                    end
                end
                ST_CONSUME: begin
                    if (sig_valid) begin
                        buffer <= buffer | ({sig, 64'b0} >> (128 - valid_buffer));
                        valid_buffer <= valid_buffer - 8'd64;
                    end
                end
                ST_GENS: begin
                    buffer <= buffer << 8;
                    valid_buffer <= valid_buffer + 8'd8;
                end
                ST_GENK: begin
                    if (buffer == 128'b0) begin
                        buffer <= 128'b0;
                        valid_buffer <= 8'd128;
                    end
                    else if (buffer[127:64] == 64'b0) begin
                            buffer <= buffer << 64;
                            valid_buffer <= valid_buffer +8'd64;
                    end
                    else if (buffer[127:96] == 32'b0) begin
                        buffer <= buffer << 32;
                        valid_buffer <= valid_buffer +8'd32;
                    end
                    else if (buffer[127:96] == 32'b0) begin
                        buffer <= buffer << 32;
                        valid_buffer <= valid_buffer +8'd32;
                    end
                    else if (buffer[127:112] == 16'b0) begin
                        buffer <= buffer << 16;
                        valid_buffer <= valid_buffer +8'd16;
                    end
                    else if (buffer[127:120] == 8'b0) begin
                        buffer <= buffer << 8;
                        valid_buffer <= valid_buffer +8'd8;
                    end
                    else if (buffer[127:124] == 4'b0) begin
                        buffer <= buffer << 4;
                        valid_buffer <= valid_buffer +8'd4;
                    end
                    else if (buffer[127:126] == 2'b0) begin
                        buffer <= buffer << 2;
                        valid_buffer <= valid_buffer +8'd2;
                    end
                    else if (buffer[127] == 1'b0) begin
                        buffer <= buffer << 1;
                        valid_buffer <= valid_buffer +8'd1;
                    end
                    else begin
                        buffer <= buffer;
                        valid_buffer <= valid_buffer;
                    end
                end
                ST_DONE: begin
                    buffer <= 128'b0;
                    valid_buffer <= 8'd128;
                end
                default: begin
                    buffer <= buffer;
                    valid_buffer <= valid_buffer;
                end
            endcase
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
                    if (coef_valid && coef_ready) begin
                        idx <= idx + 11'b1; 
                    end
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
        else if (start) begin
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
endmodule
