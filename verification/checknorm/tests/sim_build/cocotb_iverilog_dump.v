module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/CheckNorm.fst");
    $dumpvars(0, CheckNorm);
end
endmodule
