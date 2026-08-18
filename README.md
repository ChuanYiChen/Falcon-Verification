This is a system verilog implementation on Falcon verification

HashToPoint:
Input : (r||m) with each chunk 64bits
Output: Coefficients of polynomial c in Z_q[x] with degree N

Decompress:
Input : Signature of size 666/1280 bytes (Depends on Security Level)
Output: Coefficients of polynomial s_2 in Z_q[x] with degree N

Verilator command:
~/FalconVerification$ verilator --lint-only -Wall -Wno-UNUSED -Wno-IMPORTSTAR --top-module Verify_top Verilog/falcon_pkg.sv Verilog/ComputeEngine/Addq.sv Verilog/ComputeEngine/CheckNorm.sv Verilog/ComputeEngine/Decompress.sv Verilog/ComputeEngine/HashToPoint.sv Verilog/ComputeEngine/Input_Control.sv Verilog/ComputeEngine/Keccak.sv Verilog/ComputeEngine/NTT.sv Verilog/ComputeEngine/Poly_Accessor.sv Verilog/ComputeEngine/PolyMul.sv Verilog/ComputeEngine/Shake256.sv Verilog/ComputeEngine/Verify_top.sv Verilog/Memory/PolyRAM.sv Verilog/Memory/SRAM.sv

Decompress_Chunk Version:
~/FalconVerification$ verilator --lint-only -Wall -Wno-UNUSED -Wno-IMPORTSTAR --top-module Verify_top Verilog/falcon_pkg.sv Verilog/ComputeEngine/Addq.sv Verilog/ComputeEngine/CheckNorm.sv Verilog/ComputeEngine/Decompress_chunk.sv Verilog/ComputeEngine/HashToPoint.sv Verilog/ComputeEngine/Input_Control.sv Verilog/ComputeEngine/Keccak.sv Verilog/ComputeEngine/NTT.sv Verilog/ComputeEngine/Poly_Accessor.sv Verilog/ComputeEngine/PolyMul.sv Verilog/ComputeEngine/Shake256.sv Verilog/ComputeEngine/Verify_top.sv Verilog/Memory/PolyRAM.sv Verilog/Memory/SRAM.sv