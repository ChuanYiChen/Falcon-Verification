module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/Decompress_chunk.fst");
    $dumpvars(0, Decompress_chunk);
end
endmodule
