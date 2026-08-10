module PolyRAM# (
    parameter ADDR_WIDTH = 17,
    parameter COEFF_WIDTH = 64,     // Each coefficient needs 64 bits
    parameter DEPTH = 1 << 17   // The capacity of RAM is 128 polynomials  ADDR: {7bits:Poly_addr 10bits:Coef_addr}
)
(
    input clk,
    input [ADDR_WIDTH - 1:0] addrA,
    input [COEFF_WIDTH - 1:0] wdataA,
    input cenA,
    input wenA,
    output logic [COEFF_WIDTH - 1:0] rdataA,
    input [ADDR_WIDTH - 1:0] addrB,
    input [COEFF_WIDTH - 1:0] wdataB,
    input cenB,
    input wenB,
    output logic [COEFF_WIDTH - 1:0] rdataB,
    input [ADDR_WIDTH - 1:0] addrC,
    input [COEFF_WIDTH - 1:0] wdataC,
    input cenC,
    input wenC,
    output logic [COEFF_WIDTH - 1:0] rdataC
);

    logic [COEFF_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        if (cenA) begin
            if (wenA) begin
                mem[addrA] <= wdataA;   
            end
            rdataA <= mem[addrA];
        end       
    end

    always_ff @(posedge clk) begin
        if (cenB) begin
            if (wenB) begin
                mem[addrB] <= wdataB;   
            end
            rdataB <= mem[addrB];
        end       
    end

    always_ff @(posedge clk) begin
        if (cenC) begin
            if (wenC) begin
                mem[addrC] <= wdataC;   
            end
            rdataC <= mem[addrC];
        end       
    end

endmodule

//Local Variables:
//verilog-library-directories:("." "ComputeEngine" "PolySeedGenerator" "Controller" "Memory")
// verilog-library-extensions:(".sv" ".v")
// verilog-typedef-regexp:"_t$"
//End:
