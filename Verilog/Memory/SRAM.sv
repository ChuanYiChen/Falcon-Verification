module SRAM
# (
    parameter ADDR_WIDTH = 11,    
    parameter DATA_WIDTH = 64,    // Each register needs 64 bits
    parameter DEPTH = 1 << 11     // The capacity of RAM is 2048 registers
)
(
    input clk,
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] wdata,
    input cen,
    input wen,
    output logic [DATA_WIDTH-1:0] rdata
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    always_ff@(posedge clk) begin
        if(cen) begin
            if(wen) begin
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

