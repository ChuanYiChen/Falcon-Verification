module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/Shake256.fst");
    $dumpvars(0, Shake256);
end
endmodule
