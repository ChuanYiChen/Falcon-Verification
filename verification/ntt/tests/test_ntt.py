from __future__ import annotations

import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

try:
    from ntt import intt, ntt, q
except ImportError:  # pragma: no cover - fallback for local execution
    from model.ntt import intt, ntt, q

N = int(os.getenv("NTT_N", "8"))
WIDTH = 14
Q = q


def pack_polynomial(coefficients):
    value = 0
    for index, coefficient in enumerate(coefficients):
        value |= (coefficient % Q) << (index * WIDTH)
    return value


def unpack_polynomial(value):
    return [(value >> (index * WIDTH)) & ((1 << WIDTH) - 1) for index in range(N)]


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.inverse.value = 0
    dut.poly_in.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def run_transform(dut, coefficients, inverse=False):
    dut.inverse.value = int(inverse)
    dut.poly_in.value = pack_polynomial(coefficients)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    for _ in range(2000):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            await Timer(1, "ns")
            return unpack_polynomial(int(dut.poly_out.value))

    raise AssertionError(f"NTT{' inverse' if inverse else ''} did not finish in time")


@cocotb.test()
async def ntt_matches_python_model(dut):
    """Forward NTT output should match the Python reference implementation."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset_dut(dut)

    test_vectors = [
        [0, 1, 2, 3, 4, 5, 6, 7][:N],
        [((i * 17) + 3) % Q for i in range(N)],
        [((i * 31) + 9) % Q for i in range(N)],
    ]

    for coefficients in test_vectors:
        got = await run_transform(dut, coefficients, inverse=False)
        expected = ntt(coefficients)
        assert got == expected, (
            f"NTT mismatch for coefficients={coefficients}: got={got}, expected={expected}"
        )


# @cocotb.test()
async def intt_matches_python_model(dut):
    """Inverse NTT output should recover the input polynomial modulo q."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset_dut(dut)

    test_vectors = [
        [0, 1, 2, 3, 4, 5, 6, 7][:N],
        [((i * 11) + 5) % Q for i in range(N)],
        [((i * 23) + 7) % Q for i in range(N)],
    ]

    for coefficients in test_vectors:
        expected_ntt = ntt(coefficients)
        got = await run_transform(dut, expected_ntt, inverse=True)
        expected = coefficients
        assert got == expected, (
            f"INTT mismatch for coefficients={coefficients}: got={got}, expected={expected}"
        )


def test_ntt_runner():
    """Build and run the NTT cocotb tests with the selected simulator."""
    sim = os.getenv("SIM", "icarus")
    project_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(project_path / "model"))

    sources = [
        project_path.parent / "Verilog" / "falcon_pkg.sv",
        project_path.parent / "Verilog" / "ComputeEngine" / "NTT.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="NTT",
        parameters={"N": N},
        always=True,
    )
    runner.test(
        hdl_toplevel="NTT",
        test_module="test_ntt",
    )


if __name__ == "__main__":
    test_ntt_runner()
