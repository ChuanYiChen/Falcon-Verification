module PolyRAM# (
    parameter ADDR_WIDTH = 17,
    parameter COEFF_WIDTH = 64,     // Each coefficient needs 64 bits
    parameter DEPTH = 1 << 17   // The capacity of RAM is 128 polynomials  ADDR: {7bits:Poly_addr 10bits:Coef_addr}
)
(
    input clk,
    input [ADDR_WIDTH - 1:0] addr,
    input [COEFF_WIDTH - 1:0] wdata,
    input cen,
    input wen,
    output logic [COEFF_WIDTH - 1:0] rdata
);

    logic [COEFF_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        if (cen) begin
            if (wen) begin
                mem[addr] <= wdata;   
            end
            rdata <= mem[addr];
        end       
    end

endmodule

//Local Variables:
//verilog-library-directories:("." "ComputeEngine" "PolySeedGenerator" "Controller" "Memory")
// verilog-library-extensions:(".sv" ".v")
// verilog-typedef-regexp:"_t$"
//End:
