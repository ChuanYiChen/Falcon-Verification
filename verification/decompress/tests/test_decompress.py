# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0
from __future__ import annotations

import os
import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

from decompress import decompress as model_decompress


async def reset_dut(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.sig.value = 0
    dut.sig_valid.value = 0
    dut.Sec_LV.value = 0
    dut.coef_ready.value = 1

    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_sig(dut, sig: bytes) -> None:
    chunks = [sig[i : i + 8] for i in range(0, len(sig), 8)]

    for index, chunk in enumerate(chunks):
        chunk_value = int.from_bytes(chunk.ljust(8, b"\x00"), "little")

        while int(dut.sig_ready.value) == 0:
            await RisingEdge(dut.clk)

        dut.sig.value = chunk_value
        dut.sig_valid.value = 1

        await RisingEdge(dut.clk)

        dut.sig_valid.value = 0
        dut.sig.value = 0


async def collect_coeffs(dut, expected_count: int, timeout_cycles: int = 200000) -> list[int]:
    coeffs: list[int] = []
    observed_words = []

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.coef_valid.value):
            coeffs.append(int(dut.coef.value))
            if len(coeffs) >= expected_count:
                break

    if len(coeffs) != expected_count:
        raise AssertionError(
            f"Timed out collecting coefficients: got {len(coeffs)} expected {expected_count}"
        )

    return coeffs


@cocotb.test()
async def decompress_matches_python_model(dut):
    """Decompress outputs match the Python reference model."""
    await reset_dut(dut)

    test_vectors = [
        (0, b"Falcon verification test vector."),
        (1, b"Falcon verification test vector with level V."),
    ]

    for sec_lv, sig in test_vectors:
        dut.Sec_LV.value = sec_lv

        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        expected = model_decompress(sig, sec_lv=sec_lv)

        await drive_sig(dut, sig)
        got = await collect_coeffs(dut, len(expected))

        assert got == expected, (
            f"Sec_LV={sec_lv} mismatch: got {len(got)} coefficients, expected {len(expected)}"
        )

        await RisingEdge(dut.done)
        await RisingEdge(dut.clk)


@cocotb.test()
async def decompress_random_sigs_match_python_model(dut):
    """Random signature inputs match the Python reference implementation."""
    await reset_dut(dut)

    for sec_lv in (0, 1):
        for _ in range(5):
            sig = bytes(random.getrandbits(8) for _ in range(random.randint(1, 64)))
            dut.Sec_LV.value = sec_lv

            dut.start.value = 1
            await RisingEdge(dut.clk)
            dut.start.value = 0

            expected = model_decompress(sig, sec_lv=sec_lv)

            await drive_sig(dut, sig)
            got = await collect_coeffs(dut, len(expected))

            assert got == expected, (
                f"Sec_LV={sec_lv} random signature mismatch: got {len(got)} coefficients, expected {len(expected)}"
            )

            await RisingEdge(dut.done)
            await RisingEdge(dut.clk)


def test_decompress_runner() -> None:
    """Run the Decompress cocotb tests using the selected simulator."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "model"))

    sources = [
        proj_path.parent / "Verilog" / "falcon_pkg.sv",
        proj_path.parent / "Verilog" / "ComputeEngine" / "Decompress.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Decompress",
        always=True,
    )
    runner.test(
        hdl_toplevel="Decompress",
        test_module="test_decompress",
    )


if __name__ == "__main__":
    test_decompress_runner()