from __future__ import annotations

import os
import sys
from pathlib import Path
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

checknorm_path = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(checknorm_path / "model"))
sys.path.insert(0, str(checknorm_path))
from model.sign import sign as sign

Q = 12289
HALF_Q = Q >> 1
BETA_SQ_I = 34_034_726
BETA_SQ_V = 70_265_242
WIDTH = 14


async def reset_dut(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.i_valid.value = 0
    dut.o_ready.value = 0
    dut.s1_din.value = 0
    dut.s2_din.value = 0
    dut.Sec_LV.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def encode_coefficient(value: int) -> int:
    """Convert a centered Falcon coefficient into its unsigned modulo-Q form."""
    assert -HALF_Q <= value <= HALF_Q
    return value if value >= 0 else value + Q


async def run_vector(
    dut,
    s1: list[int],
    s2: list[int],
    N: int,
    expected: bool,
    hold_output: bool = False,
    level_v: bool = False,
) -> None:
    assert len(s1) == N
    assert len(s2) == N
    dut.Sec_LV.value = int(level_v)

    coefficient_index = 0
    while coefficient_index < N:
        while not int(dut.i_ready.value):
            await RisingEdge(dut.clk)

        dut.s1_din.value = encode_coefficient(s1[coefficient_index])
        dut.s2_din.value = encode_coefficient(s2[coefficient_index])
        dut.i_valid.value = 1
        await RisingEdge(dut.clk)
        coefficient_index += 1

    dut.i_valid.value = 0
    dut.s1_din.value = 0
    dut.s2_din.value = 0

    while not int(dut.o_valid.value):
        await RisingEdge(dut.clk)

    pass_signal = getattr(dut, "pass")
    assert int(pass_signal.value) == int(expected)
    if hold_output:
        for _ in range(3):
            await RisingEdge(dut.clk)
            assert int(dut.o_valid.value) == 1
            assert int(pass_signal.value) == int(expected)

    dut.o_ready.value = 1
    await RisingEdge(dut.clk)
    dut.o_ready.value = 0


@cocotb.test()
async def accepts_norm_level_i_bound(dut):
    """The exact Falcon-512 bound is accepted, including centered inputs."""
    await reset_dut(dut)

    s1 = [0] * 512
    s2 = [0] * 512
    s1[:3] = [1, -1026, 5743]
    assert sum(value * value for value in s1 + s2) <= BETA_SQ_I

    await run_vector(dut, s1, s2, 512, expected=True)


@cocotb.test()
async def rejects_norm_level_i_bound(dut):
    """A one-unit increase above the Falcon-512 bound is rejected."""
    await reset_dut(dut)

    s1 = [0] * 512
    s2 = [0] * 512
    s1[:4] = [1, -1026, 5743, 1]
    assert sum(value * value for value in s1 + s2) > BETA_SQ_I 

    await run_vector(dut, s1, s2, 512, expected=False)


@cocotb.test()
async def random_norm_level_i_bound(dut):
    """The result remains valid until the downstream side accepts it."""
    await reset_dut(dut)

    for _ in range(20):
        message = random.randbytes(16)

        s = sign(0, 512, message)
        s1, s2 = s
        await run_vector(dut, s1, s2, 512, expected=True, hold_output=True)

@cocotb.test()
async def accepts_norm_level_v_bound(dut):
    """The exact Falcon-1024 bound is accepted, including centered inputs."""
    await reset_dut(dut)

    s1 = [0] * 1024
    s2 = [0] * 1024
    s1[:6] = [1, -1026, 5743, 4, 856, 5958]
    assert sum(value * value for value in s1 + s2) <= BETA_SQ_V

    await run_vector(dut, s1, s2, 1024, expected=True, level_v=True)


@cocotb.test()
async def rejects_norm_level_v_bound(dut):
    """A one-unit increase above the Falcon-1024 bound is rejected."""
    await reset_dut(dut)

    s1 = [0] * 1024
    s2 = [0] * 1024
    s1[:7] = [1, -1026, 5743, 4, 856, 5958, 1]
    assert sum(value * value for value in s1 + s2) > BETA_SQ_V

    await run_vector(dut, s1, s2, 1024, expected=False, level_v=True)


@cocotb.test()
async def random_norm_level_v_bound(dut):
    """The result remains valid until the downstream side accepts it."""
    await reset_dut(dut)

    for _ in range(20):
        message = random.randbytes(16)

        s = sign(0, 512, message)
        s1, s2 = s
        await run_vector(dut, s1, s2, 512, expected=True, hold_output=True)


def test_checknorm_runner() -> None:
    """Build and run the CheckNorm cocotb tests."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path.parent.parent.parent / "Verilog" / "falcon_pkg.sv",
        proj_path.parent.parent.parent / "Verilog" / "ComputeEngine" / "CheckNorm.sv",
    ]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="CheckNorm", always=True)
    runner.test(hdl_toplevel="CheckNorm", test_module="test_checknorm")


if __name__ == "__main__":
    test_checknorm_runner()