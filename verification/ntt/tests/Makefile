TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)
NTT_N ?= 8
export NTT_N
export PYTHONPATH := $(PWD)/../model:$(PWD):$(PYTHONPATH)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/NTT.sv
    COMPILE_ARGS += -PNTT.N=$(NTT_N)
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := NTT
COCOTB_TEST_MODULES := test_ntt

include $(shell cocotb-config --makefiles)/Makefile.sim
