module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/Keccak.fst");
    $dumpvars(0, Keccak);
end
endmodule
