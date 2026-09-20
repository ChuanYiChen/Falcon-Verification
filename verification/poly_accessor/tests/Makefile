TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)
POLY_ACCESSOR_N ?= 16
export POLY_ACCESSOR_N

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Poly_Accessor.sv
    COMPILE_ARGS += -PPoly_Accessor.N=$(POLY_ACCESSOR_N)
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := Poly_Accessor
COCOTB_TEST_MODULES := test_poly_accessor

include $(shell cocotb-config --makefiles)/Makefile.sim
