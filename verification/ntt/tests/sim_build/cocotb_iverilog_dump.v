module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/NTT.fst");
    $dumpvars(0, NTT);
end
endmodule
