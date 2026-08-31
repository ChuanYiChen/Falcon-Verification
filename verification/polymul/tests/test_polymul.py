import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

try:
    from ntt import mul_zq
except ImportError:  # pragma: no cover - fallback for direct local execution
    from model.ntt import mul_zq

Q = 12289
N = int(os.getenv("POLYMUL_N", "8"))
WIDTH = 14


def pack_polynomial(coefficients):
    value = 0
    for index, coefficient in enumerate(coefficients):
        value |= (coefficient % Q) << (index * WIDTH)
    return value


def unpack_polynomial(value):
    mask = (1 << WIDTH) - 1
    return [(value >> (index * WIDTH)) & mask for index in range(N)]


def expected_product(a_coefficients, b_coefficients):
    result = mul_zq(a_coefficients, b_coefficients)
    return result

async def multiply(dut, a_coefficients, b_coefficients):
    dut.a_in.value = pack_polynomial(a_coefficients)
    dut.b_in.value = pack_polynomial(b_coefficients)

    while not int(dut.in_ready.value):
        await RisingEdge(dut.clk)

    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    while not int(dut.done.value):
        await RisingEdge(dut.clk)

    await Timer(1, "ns")
    result = unpack_polynomial(int(dut.prod_out.value))

    dut.prod_out_ready.value = 1
    await RisingEdge(dut.clk)
    dut.prod_out_ready.value = 0
    return result


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.prod_out_ready.value = 0
    dut.a_in.value = 0
    dut.b_in.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def polymul_matches_cyclic_convolution(dut):
    """Compare the DUT with multiplication in Z_q[x]/(x^N - 1)."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset_dut(dut)

    test_vectors = [
        ([1] + [0] * (N - 1), [0, 1] + [0] * (N - 2)),
        ([Q - 1] * N, [2] + [0] * (N - 1)),
        (
            [index + 1 for index in range(N)],
            [3 * index % Q for index in range(N)],
        ),
    ]

    for a_coefficients, b_coefficients in test_vectors:
        got = await multiply(dut, a_coefficients, b_coefficients)
        expected = expected_product(a_coefficients, b_coefficients)
        assert got == expected, f"polynomial mismatch: got={got}, expected={expected}"


# @cocotb.test()
async def polymul_random_vectors(dut):
    """Exercise several random coefficient vectors modulo q."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset_dut(dut)
    random_generator = random.Random(0xFA1C0)

    for _ in range(3):
        a_coefficients = [random_generator.randrange(Q) for _ in range(N)]
        b_coefficients = [random_generator.randrange(Q) for _ in range(N)]
        got = await multiply(dut, a_coefficients, b_coefficients)
        expected = expected_product(a_coefficients, b_coefficients)
        assert got == expected, f"random mismatch: got={got}, expected={expected}"


def test_polymul_runner():
    """Simulate PolyMul with the selected HDL simulator."""
    sim = os.getenv("SIM", "icarus")
    project_path = Path(__file__).resolve().parents[3]
    sources = [
        project_path / "Verilog" / "falcon_pkg.sv",
        project_path / "Verilog" / "ComputeEngine" / "NTT.sv",
        project_path / "Verilog" / "ComputeEngine" / "PolyMul.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="PolyMul",
        parameters={"N": N},
        always=True,
    )
    runner.test(hdl_toplevel="PolyMul", test_module="test_polymul")


if __name__ == "__main__":
    test_polymul_runner()