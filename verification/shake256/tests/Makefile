# SPDX-License-Identifier: BSD-3-Clause
TOPLEVEL_LANG ?= verilog

PWD=$(shell pwd)

export PYTHONPATH := $(PWD):$(PYTHONPATH)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = \
		$(PWD)/../../../Verilog/ComputeEngine/Shake256.sv \
		$(PWD)/../../../Verilog/ComputeEngine/Keccak.sv
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := Shake256
COCOTB_TEST_MODULES := test_shake256

include $(shell cocotb-config --makefiles)/Makefile.sim
