TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)

export PYTHONPATH := $(PWD)/../model:$(PWD)/../../../../falcon.py:$(PYTHONPATH)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Decompress_chunk.sv
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := Decompress_chunk
COCOTB_TEST_MODULES := test_decompress

include $(shell cocotb-config --makefiles)/Makefile.sim