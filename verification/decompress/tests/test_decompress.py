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
    from decompress import compress as model_compress
    from decompress import decompress as model_decompress
except ImportError:  # pragma: no cover - fallback for direct local execution
    from model.decompress import compress as model_compress
    from model.decompress import decompress as model_decompress


WIDTH = 14
SIG_LEN_I = 666
SIG_LEN_V = 1280
N_I = 512
N_V = 1024
HEADER_AND_NONCE_LEN = 41


async def reset_dut(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.sig_valid.value = 0
    dut.sig.value = 0
    dut.Sec_LV.value = 0
    dut.coef_ready.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def encode_input(coefficients: list[int], sec_lv: int) -> tuple[list[int], list[int]]:
    """Encode coefficients into the 64-bit chunks consumed by the RTL."""
    n = N_V if sec_lv else N_I
    signature_length = SIG_LEN_V if sec_lv else SIG_LEN_I
    payload_length = signature_length - HEADER_AND_NONCE_LEN

    encoded = model_compress(coefficients, payload_length)
    # print(f"ENCODED: {encoded}")
    assert encoded is not False
    expected = model_decompress(encoded, payload_length, n)
    # print(f"EXPECTED: {expected}")
    assert expected is not False

    chunks = [
        int.from_bytes(encoded[index : index + 8].ljust(8, b"\x00"), "big")
        for index in range(0, len(encoded), 8)
    ]
    return chunks, expected


def signed_coefficient(value: int) -> int:
    value &= (1 << WIDTH) - 1
    return value - (1 << WIDTH) if value & (1 << (WIDTH - 1)) else value


async def run_vector(dut, coefficients: list[int], sec_lv: int, seed: int) -> None:
    chunks, expected = encode_input(coefficients, sec_lv)
    print(f"EXPECTED: {expected[:10]}")
    print("=" * 10)

    dut.Sec_LV.value = sec_lv
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    got = []
    chunk_index = 0
    sig_pending = False

    while len(got) < len(expected) or chunk_index < len(chunks):
        if not sig_pending and chunk_index < len(chunks) and int(dut.sig_ready.value):
            dut.sig.value = chunks[chunk_index]
            dut.sig_valid.value = 1
            sig_pending = True

        dut.coef_ready.value = 1
        await Timer(1, "ns")

        sig_accepted = sig_pending and int(dut.sig_ready.value)
        coefficient_accepted = (
            int(dut.coef_valid.value)
            and int(dut.coef_ready.value)
        )
        if coefficient_accepted:
            got.append(signed_coefficient(int(dut.coef.value)))
            if len(got) <= 12:
                dut._log.info("coefficient %d = %d", len(got) - 1, got[-1])

        await RisingEdge(dut.clk)

        if sig_accepted:
            chunk_index += 1
            sig_pending = False
            dut.sig_valid.value = 0
            dut.sig.value = 0

    assert got == expected, (
        f"Sec_LV={sec_lv} coefficient mismatch: "
        f"got {got[:12]}..., expected {expected[:12]}..."
    )

    dut.coef_ready.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
        if int(dut.done.value):
            break
    else:
        raise AssertionError("Decompress did not assert done")

    assert int(dut.fail.value) == 0


@cocotb.test()
async def decompress_level_i_matches_python_model(dut):
    """Level I output matches encoding.decompress with backpressure applied."""
    await reset_dut(dut)
    coefficients = [0, 1, -1, 127, -127, 128, -128, 255, -255] + [0] * (N_I - 9)
    await run_vector(dut, coefficients, sec_lv=0, seed=1)


# @cocotb.test()
async def decompress_level_v_matches_python_model(dut):
    """Level V output matches encoding.decompress with backpressure applied."""
    await reset_dut(dut)
    coefficients = [0, -1, 1, -128, 128, -255, 255, 1024, -1024] + [0] * (N_V - 9)
    await run_vector(dut, coefficients, sec_lv=1, seed=2)


def test_decompress_runner() -> None:
    """Build and run the Decompress cocotb tests via cocotb-tools."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "model"))
    sys.path.append(str(proj_path.parent.parent.parent / "falcon.py"))

    sources = [
        proj_path.parent.parent / "Verilog" / "falcon_pkg.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Decompress_chunk.sv",
    ]

    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="Decompress_chunk", always=True)
    runner.test(hdl_toplevel="Decompress_chunk", test_module="test_decompress")


if __name__ == "__main__":
    test_decompress_runner()