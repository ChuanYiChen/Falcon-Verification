TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Keccak.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Shake256.sv \
        $(PWD)/../../../Verilog/ComputeEngine/HashToPoint.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Decompress_chunk.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Input_Control.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Poly_Accessor.sv \
        $(PWD)/../../../Verilog/Memory/PolyRAM.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Verify_top.sv
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := Verify_top
COCOTB_TEST_MODULES := test_verify_top

include $(shell cocotb-config --makefiles)/Makefile.sim
