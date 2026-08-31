module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/PolyMul.fst");
    $dumpvars(0, PolyMul);
end
endmodule
