import falcon_pkg::*;

module NTTRAM #(parameter int N = 512)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  i_valid,
    input  logic                  o_ready,
    output logic                  i_ready,
    output logic                  o_valid,
    input  logic [WIDTH-1:0]      coef_in,
    input  logic [9:0]            coef_addr,
    output logic [WIDTH-1:0]      poly_out
);

    logic [9:0] counter;

    assign i_ready = !(o_valid && !o_ready);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poly_out <= 'b0;
            counter <= 'b0;
        end
        else begin
            if (o_valid && o_ready) begin
                poly_out <= 'b0;
                counter <= 'b0;
            end
            else if (i_valid && i_ready) begin
                //poly_out [coef_addr*WIDTH + N - 1: coef_addr*WIDTH] <= coef_in;
                poly_out <= poly_out | {(N*WIDTH - coef_addr*WIDTH - WIDTH)'b0, coef_in ,(coef_addr*WIDTH)'b0}
                counter <= counter + 10'd1;        
            end
            else begin
                poly_out <= poly_out;
                counter <= 'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid <= 'b0;
        end
        else if (o_valid && o_ready) begin
            o_valid <= 'b0;
        end
        else if ((counter[9:0] == (N-10'd1)) && i_valid && i_ready) begin
            o_valid <= 'b1;
        end
        else begin
            o_valid <= o_valid;
        end
    end
endmodule