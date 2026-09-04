TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/CheckNorm.sv
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := CheckNorm
COCOTB_TEST_MODULES := test_checknorm

include $(shell cocotb-config --makefiles)/Makefile.sim