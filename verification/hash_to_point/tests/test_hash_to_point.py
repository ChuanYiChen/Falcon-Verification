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

from hash_to_point import hash_to_point as model_hash_to_point


async def reset_dut(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.message.value = 0
    dut.message_valid.value = 0
    dut.message_last.value = 0
    dut.message_last_bytes.value = 0
    dut.Sec_LV.value = 0
    dut.coef_ready.value = 1

    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive_message(dut, message: bytes) -> None:
    chunks = [message[i : i + 8] for i in range(0, len(message), 8)]

    for index, chunk in enumerate(chunks):
        last = index == len(chunks) - 1
        chunk_value = int.from_bytes(chunk.ljust(8, b"\x00"), "little")
        last_bytes = len(chunk) if last and len(chunk) < 8 else 0

        while int(dut.message_ready.value) == 0:
            await RisingEdge(dut.clk)

        dut.message.value = chunk_value
        dut.message_valid.value = 1
        dut.message_last.value = int(last)
        dut.message_last_bytes.value = last_bytes

        await RisingEdge(dut.clk)

        dut.message_valid.value = 0
        dut.message_last.value = 0
        dut.message_last_bytes.value = 0
        dut.message.value = 0


async def collect_coeffs(dut, expected_count: int, timeout_cycles: int = 200000) -> list[int]:
    coeffs: list[int] = []
    observed_words = []

    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.shake_dout_valid.value) and len(observed_words) < 4:
            observed_words.append(dut.shake_dout.value)
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
async def hash_to_point_matches_python_model(dut):
    """HashToPoint outputs match the Python reference model."""
    await reset_dut(dut)

    test_vectors = [
        (0, b"Falcon verification test vector."),
        (1, b"Falcon verification test vector with level V."),
    ]

    for sec_lv, message in test_vectors:
        dut.Sec_LV.value = sec_lv

        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        expected = model_hash_to_point(message, sec_lv=sec_lv)

        await drive_message(dut, message)
        got = await collect_coeffs(dut, len(expected))

        assert got == expected, (
            f"Sec_LV={sec_lv} mismatch: got {len(got)} coefficients, expected {len(expected)}"
        )


@cocotb.test()
async def hash_to_point_random_messages_match_python_model(dut):
    """Random message inputs match the Python reference implementation."""
    await reset_dut(dut)

    for sec_lv in (0, 1):
        for _ in range(5):
            message = bytes(random.getrandbits(8) for _ in range(random.randint(1, 64)))
            dut.Sec_LV.value = sec_lv

            dut.start.value = 1
            await RisingEdge(dut.clk)
            dut.start.value = 0

            expected = model_hash_to_point(message, sec_lv=sec_lv)

            await drive_message(dut, message)
            got = await collect_coeffs(dut, len(expected))

            assert got == expected, (
                f"Sec_LV={sec_lv} random message mismatch: got {len(got)} coefficients, expected {len(expected)}"
            )


def test_hash_to_point_runner() -> None:
    """Run the HashToPoint cocotb tests using the selected simulator."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "model"))

    sources = [
        proj_path.parent / "Verilog" / "falcon_pkg.sv",
        proj_path.parent / "Verilog" / "ComputeEngine" / "Shake256.sv",
        proj_path.parent / "Verilog" / "ComputeEngine" / "HashToPoint.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="HashToPoint",
        always=True,
    )
    runner.test(
        hdl_toplevel="HashToPoint",
        test_module="test_hash_to_point",
    )


if __name__ == "__main__":
    test_hash_to_point_runner()
