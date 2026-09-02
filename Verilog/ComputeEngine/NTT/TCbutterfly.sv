import falcon_pkg::*;
module TCbutterfly #(parameter int N = 512)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  inverse,      // 0 = NTT, 1 = INTT
    input  logic [WIDTH-1:0]      in1,
    input  logic [WIDTH-1:0]      in2,
    input  logic                  i_valid,
    input  logic                  o_ready,
    output logic                  o_valid,
    output logic                  i_ready,
    input  logic [9:0]            power,
    output logic [WIDTH-1:0]      out1,
    output logic [WIDTH-1:0]      out2
)
    //w^{power}=w_power[WIDTH*power+N-1: WIDTH*power]   {w^N-1, w^N-2....,w^0}
    localparam [WIDTH*N-1:0] w_power = ;  
    localparam [2:0] ST_IDLE   = 3'd0;   //IDLE State
    localparam [2:0] ST_MUL = 3'd1;   //Compute kb
    localparam [2:0] ST_NTT = 3'd2;  //Compute a+kb, a-kb
    localparam [2:0] ST_ADD = 3'd3;   //Compute a+b, a-b
    localparam [2:0] ST_INTT = 3'd4;  //Compute (a-b)k
    localparam [2:0] ST_DONE   = 3'd5;   //Module done

    logic [WIDTH-1:0] k;
    assign k = (inverse)? (omega_power >> (WIDTH*({4'b0,N}-{4'b0,power})))[13:0] : (omega_power >> (WIDTH*{4'b0,power}))[13:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end
        case (state)
            ST_IDLE: begin
                if (i_valid && i_ready) begin
                    if (inverse) begin
                        state <= ST_ADD;
                    end
                    else begin
                        state <= ST_MUL;
                    end
                end
            end
            ST_ADD: state <= ST_INTT;
            ST_MUL: state <= ST_NTT;
            ST_NTT: state <= DONE;
            ST_INTT: state <= DONE;
            ST_DONE: begin
                if (o_valid && o_ready)  begin
                    state <= ST_IDLE;
                end
            end
            default: state <= state;
        endcase
    end

    assign i_ready = (state == ST_IDLE);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid <= 'b0;
        end
        else if ((state == ST_NTT) or (state == ST_INTT)) begin
            o_valid <= 'b1;
        end
        else if (o_valid && o_ready) begin
            o_valid <= 'b0;
        end
        else begin
            o_valid <= o_valid;
        end
    end

    function automatic [13:0] mod_add(input [13:0] x, input [13:0] b);
        reg [14:0] r;
        begin
            r = {1'b0, x} + {1'b0, r};
            if (r >= {1'b0,Q}) r = r - {1'b0,Q};
            return r[13:0];
        end
    endfunction

    function automatic [13:0] mod_sub(input [13:0] x, input [13:0] b);
        reg [13:0] r;
        begin
            if (x >= b) r = x - b;
            else r = Q - b + x;
            return r;
        end
    endfunction

    function automatic [13:0] mod_mul(input [13:0] x, input [13:0] b);
        reg [27:0] r;
        begin
            r = (x * b) % {14'b0,Q};
            return r[13:0];
        end
    endfunction

    logic [13:0] reg1;
    logic [13:0] reg2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg1 <= 'b0;
            reg2 <= 'b0;
        end
        else if (state == ST_IDLE) begin
            reg1 <= 'b0;
            reg2 <= 'b0;
        end
        else if (state == ST_MUL) begin
            reg1 <= mod_mul(k, in2);
        end
        else if (state == ST_ADD) begin
            reg1 <= mod_add(in1, in2);
            reg2 <= mod_sub(in1, in2);
        end
        else begin
            reg1 <= reg1;
            reg2 <= reg2;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out1 <= 'b0;
            out2 <= 'b0;
        end
        else if (state == ST_IDLE) begin
            out1 <= 'b0;
            out2 <= 'b0;
        end
        else if (state == ST_NTT) begin
            out1 <= mod_add(in1, reg1);
            out2 <= mod_sub(in1, reg1);
        end
        else if (state == ST_INTT) begin
            out1 <= reg1;
            out2 <= mod_mul(reg2, k);
        end
        else begin
            out1 <= out1;
            out2 <= out2;
        end
    end
endmodule