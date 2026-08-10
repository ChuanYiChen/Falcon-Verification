import falcon_pkg::*;

module Addq (
    input  logic clk,
    input  logic rst_n,

    input  logic i_valid,
    input  logic o_ready,
    output logic i_ready,
    output logic o_valid,

    input  logic [WIDTH-1:0] din1,
    input  logic [WIDTH-1:0] din2,
    output logic signed [WIDTH-1:0] dout,

    input  logic sub   // 0:Add, 1:Sub
);

    logic [WIDTH:0] op;
    logic [WIDTH:0] sum;
    logic signed [WIDTH:0] centered;

    assign op   = sub ? (Q - din2) : {1'b0, din2};
    assign sum  = {1'b0, din1} + op;

    // Reduce mod Q, then center
    assign centered = (sum >= {1'b0, Q}) ? (sum - {1'b0, Q}) : sum;
    assign dout     = 14'(centered - HALFQ);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_ready <= 1'b1;
        end
        else if (o_valid && (!o_ready))begin
            i_ready <= 1'b0;
        end
        else begin
            i_ready <= i_ready;
        end
    end
    assign o_valid = i_valid && i_ready;
endmodule
