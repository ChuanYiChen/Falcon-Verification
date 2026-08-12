from __future__ import annotations

import os
import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

try:
    from keccak_model import keccak_f1600 as model_keccak
except ImportError:  # pragma: no cover - fallback for local execution
    from model.keccak_model import keccak_f1600 as model_keccak


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def set_input_state(dut, state):
    for i in range(25):
        getattr(dut, f"di{i}").value = int(state[i])


def read_output_state(dut):
    out = [0] * 25
    for i in range(25):
        out_name = f"dut.do{i}.value"
        out[i] = eval(out_name)
    return out


@cocotb.test()
async def keccak_zero_state(dut):
    """Apply an all-zero state to the Keccak core and compare to Python model."""

    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    await reset_dut(dut)

    state = [0] * 25
    set_input_state(dut, state)

    # pulse start
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # wait for ready
    for _ in range(2000):
        await RisingEdge(dut.clk)
        if int(dut.ready.value):
            break
    else:
        raise cocotb.result.TestFailure("Keccak core did not assert ready in time")

    got = read_output_state(dut)
    expected = model_keccak(state)

    assert got == expected, f"Keccak zero-state mismatch: got={got} expected={expected}"


@cocotb.test()
async def keccak_random_states(dut):
    """Feed random states and compare outputs against the Python model."""

    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    for _ in range(10):
        await reset_dut(dut)

        state = [random.getrandbits(64) for _ in range(25)]
        set_input_state(dut, state)

        # pulse start
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        # wait for ready
        for _ in range(2000):
            await RisingEdge(dut.clk)
            if int(dut.ready.value):
                break
        else:
            raise cocotb.result.TestFailure("Keccak core did not assert ready in time")

        got = read_output_state(dut)
        expected = model_keccak(state)

        assert got == expected, "Random Keccak state mismatch"


def test_keccak_runner():
    """Build and run the Keccak cocotb tests via cocotb-tools."""
    hdl_toplevel_lang = os.getenv("TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "model"))

    sources = [proj_path.parent / "Verilog" / "ComputeEngine" / "Keccak.sv"]
    build_test_args = []

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Keccak",
        always=True,
        build_args=build_test_args,
    )
    runner.test(
        hdl_toplevel="Keccak",
        test_module="test_keccak",
        test_args=build_test_args,
    )


if __name__ == "__main__":
    test_keccak_runner()
