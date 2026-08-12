# Copyright cocotb contributors
# SPDX-License-Identifier: BSD-3-Clause

TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)

export PYTHONPATH := $(PWD)/../model:$(PYTHONPATH)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
        $(PWD)/../../../Verilog/falcon_pkg.sv \
        $(PWD)/../../../Verilog/ComputeEngine/Shake256.sv \
		$(PWD)/../../../Verilog/ComputeEngine/Keccak.sv \
        $(PWD)/../../../Verilog/ComputeEngine/HashToPoint.sv
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL := HashToPoint
COCOTB_TEST_MODULES := test_hash_to_point

include $(shell cocotb-config --makefiles)/Makefile.sim
