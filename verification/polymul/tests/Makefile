TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)

POLYMUL_N ?= 8
export POLYMUL_N
export PYTHONPATH := $(PWD)/../model:$(PWD):$(PYTHONPATH)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/NTT.sv \
        $(PWD)/../../../Verilog/ComputeEngine/PolyMul.sv
    COMPILE_ARGS += -PPolyMul.N=$(POLYMUL_N)
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := PolyMul
COCOTB_TEST_MODULES := test_polymul

include $(shell cocotb-config --makefiles)/Makefile.sim