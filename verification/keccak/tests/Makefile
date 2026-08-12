# Makefile to run cocotb tests for Keccak
TOPLEVEL_LANG ?= verilog

PWD=$(shell pwd)

export PYTHONPATH := $(PWD)/../model:$(PYTHONPATH)

ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES = $(PWD)/../../../Verilog/ComputeEngine/Keccak.sv
else
    $(error A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG))
endif

COCOTB_TOPLEVEL     := Keccak
COCOTB_TEST_MODULES := test_keccak

include $(shell cocotb-config --makefiles)/Makefile.sim
