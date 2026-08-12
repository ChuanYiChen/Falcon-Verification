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

import hashlib


async def read_clean_int(sig, clk=None):
    """Read a vector signal and wait until it contains no X/Z before returning int."""
    # Try converting; if unknown bits present, wait for the next clock edge and retry.
    while True:
        s = sig.value
        try:
            return int(s)
        except ValueError:
            if clk is not None:
                await RisingEdge(clk)
            else:
                await Timer(1, "ns")


async def reset_and_start(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.absorb.value = 0
    dut.din.value = 0
    dut.din_last.value = 0
    dut.din_last_bytes.value = 0
    dut.dout_ready.value = 0
    await Timer(20, "ns")

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


@cocotb.test()
async def shake_matches_hashlib(dut):
    """Drive 64-bit words into the SHAKE wrapper and compare outputs to hashlib.shake_256."""

    # Prepare a fixed message of 4 words (little-endian packing)
    words = [
        0x6162636465666768,
        0x696a6b6c6d6e6f70,
        0x7172737475767778,
        0x797a616263646566,
    ]
    message = b"".join(w.to_bytes(8, "little") for w in words)

    # We'll request 4 output words from SHAKE and compare
    n_words = 4

    await reset_and_start(dut)

    shake = hashlib.shake_256()
    shake.update(message)
    out_bytes = shake.digest(n_words * 8)
    expected = [int.from_bytes(out_bytes[i * 8 : (i + 1) * 8], "little") for i in range(n_words)]

    # Absorb phase: drive words when dut.ready is asserted
    sent = 0
    while sent <= len(words):
        if int(dut.ready.value):
            dut.absorb.value = 1
            dut.din.value = words[sent % len(words)]
            # mark last word with din_last=1 and din_last_bytes=0 (full-word)
            if (sent == (len(words) - 1)):
                dut.din_last.value = 1 
            else:
                dut.din_last.value = 0
            dut.din_last_bytes.value = 0
            await RisingEdge(dut.clk)
            dut.absorb.value = 0
            dut.din_last.value = 0
            sent += 1
        else:
            await RisingEdge(dut.clk)

    got = []
    dut.dout_ready.value = 1
    while len(got) < 4:
        await RisingEdge(dut.clk)
        if (int(dut.state.value) == 5) and (dut.keccak_ready.value):
            await RisingEdge(dut.clk)
        if int(dut.dout_valid.value):
            val = int(dut.dout.value)
            got.append(val)

    dut.dout_ready.value = 0

    assert got == expected, f"SHAKE mismatch: got {got}, expected {expected}"


@cocotb.test()
async def shake_random_words_match_hashlib(dut):
    """Generate random messages (1-8 words) and compare DUT output to hashlib.shake_256."""

    for _ in range(20):
        num_words = random.randint(1, 8)
        words = [random.getrandbits(64) for _ in range(num_words)]
        message = b"".join(w.to_bytes(8, "little") for w in words)

        n_words = num_words  # compare same number of output words

        await reset_and_start(dut)

        shake = hashlib.shake_256()
        shake.update(message)
        out_bytes = shake.digest(n_words * 8)
        expected = [int.from_bytes(out_bytes[i * 8 : (i + 1) * 8], "little") for i in range(n_words)]

        # Absorb phase
        sent = 0
        while sent < len(words):
            if int(dut.ready.value):
                dut.absorb.value = 1
                dut.din.value = words[sent]
                dut.din_last.value = 1 if (sent == len(words) - 1) else 0
                dut.din_last_bytes.value = 0
                await RisingEdge(dut.clk)
                dut.absorb.value = 0
                dut.din_last.value = 0
                sent += 1
            else:
                await RisingEdge(dut.clk)

        # Squeeze
        # Wait for Keccak permutation to complete
        if hasattr(dut, "u_keccak"):
            while int(dut.u_keccak.ready.value):
                await RisingEdge(dut.clk)
            while not int(dut.u_keccak.ready.value):
                await RisingEdge(dut.clk)
            for _ in range(3):
                await RisingEdge(dut.clk)

        got = []
        dut.dout_ready.value = 1
        while len(got) < n_words:
            await RisingEdge(dut.clk)
            if int(dut.dout_valid.value):
                val = await read_clean_int(dut.dout, clk=dut.clk)
                got.append(val)

        dut.dout_ready.value = 0

        assert got == expected, (
            f"Random SHAKE mismatch: got {len(got)} words, expected {len(expected)}"
        )


def test_shake_runner():
    """Simulate the Shake256 module using cocotb."""
    sim = os.getenv("SIM", "icarus")

    # project root is three parents up from tests file
    proj_root = Path(__file__).resolve().parents[3]

    sources = [
        proj_root / "Verilog" / "ComputeEngine" / "Shake256.sv",
        proj_root / "Verilog" / "ComputeEngine" / "Keccak.sv",
        ]
    build_test_args = []

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Shake256",
        always=True,
        build_args=build_test_args,
    )
    runner.test(
        hdl_toplevel="Shake256",
        test_module="test_shake256",
        test_args=build_test_args,
    )


if __name__ == "__main__":
    test_shake_runner()
