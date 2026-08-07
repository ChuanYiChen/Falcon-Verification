import falcon_pkg::*;

module PolyMul #(parameter int N = 512) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [N*WIDTH-1:0]    a_in,
    input  logic [N*WIDTH-1:0]    b_in,
    output logic [N*WIDTH-1:0]    prod_out,
    output logic                  done
);

    localparam [2:0] ST_IDLE      = 0;
    localparam [2:0] ST_WAIT_NTT  = 1;
    localparam [2:0] ST_POINTWISE = 2;
    localparam [2:0] ST_WAIT_INTT = 3;
    localparam [2:0] ST_DONE      = 4;

    logic [2:0] state;

    logic [N*WIDTH-1:0] a_ntt_out;
    logic [N*WIDTH-1:0] b_ntt_out;
    logic [N*WIDTH-1:0] c_ntt;
    logic [N*WIDTH-1:0] intt_out;

    logic a_start, b_start, c_start;
    logic a_done, b_done, c_done;

    integer i;

    function automatic integer mod_mul(input integer a, input integer b);
        return (a * b) % {18'b0, Q};
    endfunction

    NTT #(.N(N)) u_ntt_a (
        .clk(clk),
        .rst_n(rst_n),
        .start(a_start),
        .inverse(1'b0),
        .poly_in(a_in),
        .poly_out(a_ntt_out),
        .done(a_done)
    );

    NTT #(.N(N)) u_ntt_b (
        .clk(clk),
        .rst_n(rst_n),
        .start(b_start),
        .inverse(1'b0),
        .poly_in(b_in),
        .poly_out(b_ntt_out),
        .done(b_done)
    );

    NTT #(.N(N)) u_intt (
        .clk(clk),
        .rst_n(rst_n),
        .start(c_start),
        .inverse(1'b1),
        .poly_in(c_ntt),
        .poly_out(intt_out),
        .done(c_done)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            a_start <= 1'b0;
            b_start <= 1'b0;
            c_start <= 1'b0;
            done <= 1'b0;
            prod_out <= '0;
        end else begin
            case (state)

                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        a_start <= 1'b1;
                        b_start <= 1'b1;
                        c_start <= 1'b0;
                        state <= ST_WAIT_NTT;
                    end
                end

                ST_WAIT_NTT: begin
                    a_start <= 1'b0;
                    b_start <= 1'b0;
                    state <= ST_POINTWISE;
                end
                
                //pointwise multiplication
                ST_POINTWISE: begin
                    for (i = 0; i < N; i++) begin
                        integer ta, tb, tc;
                        ta = {18'b0, a_ntt_out[i*WIDTH +: WIDTH]};
                        tb = {18'b0, b_ntt_out[i*WIDTH +: WIDTH]};
                        tc = mod_mul(ta, tb);
                        c_ntt[i*WIDTH +: WIDTH] = tc[13:0];
                    end
                    c_start <= 1'b1;
                    state <= ST_WAIT_INTT;
                end

                ST_WAIT_INTT: begin
                    c_start <= 1'b0;
                    prod_out <= intt_out;
                    done <= 1'b1;
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    if (start) begin
                        a_start <= 1'b1;
                        b_start <= 1'b1;
                        c_start <= 1'b0;
                        state <= ST_WAIT_NTT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
