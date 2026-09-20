from __future__ import annotations

import os
import random
from dataclasses import dataclass
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

# Poly_Accessor's own I/O documentation: 0=IDLE, 1=HashToPoint, 2=Decompress.
ST_IDLE = 0
ST_HTP = 1
ST_DECOMPRESS = 2
ST_UNUSED = 3  # any other encoding must behave like the "default: hold" branches

N = int(os.getenv("POLY_ACCESSOR_N", "16"))
WIDTH = 14
COEF_MASK = (1 << WIDTH) - 1

HTP_TAG = 0
DECOMPRESS_TAG = 1


async def reset_dut(dut) -> None:
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.state.value = ST_IDLE
    dut.htp_coef.value = 0
    dut.htp_coef_valid.value = 0
    dut.decompress_coef.value = 0
    dut.decompress_coef_valid.value = 0
    dut.r_coef.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@dataclass
class ShadowState:
    """Cycle-accurate re-implementation of the registers inside Poly_Accessor.sv.

    Poly_Accessor has no algorithmic "golden model" of its own (it is a small
    RAM-write sequencer), so its specification *is* the RTL's register-transfer
    description. Re-deriving that description independently in Python and
    comparing every cycle against the DUT is the meaningful check here.
    """

    n: int
    i_counter: int = 0
    w_coef: int = 0
    poly_addr: int = 0
    en: int = 0

    def reset(self) -> None:
        self.i_counter = 0
        self.w_coef = 0
        self.poly_addr = 0
        self.en = 0

    def combinational(self, state: int, htp_valid: int, decompress_valid: int):
        htp_ready = int(state == ST_HTP and htp_valid)
        decompress_ready = int(state == ST_DECOMPRESS and decompress_valid)
        done = int(
            (state == ST_HTP and htp_valid and htp_ready and self.i_counter == self.n)
            or (
                state == ST_DECOMPRESS
                and decompress_valid
                and decompress_ready
                and self.i_counter == self.n
            )
        )
        return htp_ready, decompress_ready, done

    def advance(
        self,
        state: int,
        htp_coef: int,
        htp_valid: int,
        decompress_coef: int,
        decompress_valid: int,
    ) -> None:
        htp_ready, decompress_ready, _ = self.combinational(state, htp_valid, decompress_valid)

        if self.i_counter == self.n:
            next_counter = 0
        elif state == ST_HTP and htp_valid and htp_ready:
            next_counter = self.i_counter + 1
        elif state == ST_DECOMPRESS and decompress_valid and decompress_ready:
            next_counter = self.i_counter + 1
        else:
            next_counter = self.i_counter

        if state == ST_HTP:
            next_w_coef = htp_coef & COEF_MASK
            next_poly_addr = (HTP_TAG << 10) | (self.i_counter & 0x3FF)
            next_en = (htp_valid << 1) | 1
        elif state == ST_DECOMPRESS:
            next_w_coef = decompress_coef & COEF_MASK
            next_poly_addr = (DECOMPRESS_TAG << 10) | (self.i_counter & 0x3FF)
            next_en = (decompress_valid << 1) | 1
        else:
            next_w_coef = self.w_coef
            next_poly_addr = self.poly_addr
            next_en = self.en

        self.i_counter = next_counter
        self.w_coef = next_w_coef
        self.poly_addr = next_poly_addr
        self.en = next_en


async def drive_cycle(
    dut,
    shadow: ShadowState,
    state: int,
    htp_coef: int = 0,
    htp_valid: int = 0,
    decompress_coef: int = 0,
    decompress_valid: int = 0,
    writes: list | None = None,
) -> None:
    """Apply one cycle of inputs, check every DUT output against the shadow
    model, then advance both the DUT and the shadow model by one clock edge.

    `writes` (if given) collects (addr, data) pairs for cycles where the
    write-enable pair {cen, wen} is asserted, so callers can reconstruct what
    would actually land in PolyRAM.
    """
    dut.state.value = state
    dut.htp_coef.value = htp_coef & COEF_MASK
    dut.htp_coef_valid.value = htp_valid
    dut.decompress_coef.value = decompress_coef & COEF_MASK
    dut.decompress_coef_valid.value = decompress_valid

    await Timer(1, "ns")

    exp_htp_ready, exp_decompress_ready, exp_done = shadow.combinational(
        state, htp_valid, decompress_valid
    )

    assert int(dut.htp_coef_ready.value) == exp_htp_ready
    assert int(dut.decompress_coef_ready.value) == exp_decompress_ready
    assert int(dut.done.value) == exp_done
    assert int(dut.poly_addr.value) == shadow.poly_addr
    assert int(dut.w_coef.value) == shadow.w_coef
    assert int(dut.en.value) == shadow.en

    if writes is not None and shadow.en == 0b11:
        writes.append((shadow.poly_addr, shadow.w_coef))

    await RisingEdge(dut.clk)
    shadow.advance(state, htp_coef, htp_valid, decompress_coef, decompress_valid)


@cocotb.test()
async def reset_clears_all_outputs(dut):
    """After reset, every DUT output should be at its zero default."""
    await reset_dut(dut)
    shadow = ShadowState(n=N)

    assert int(dut.en.value) == 0
    assert int(dut.poly_addr.value) == 0
    assert int(dut.w_coef.value) == 0
    assert int(dut.done.value) == 0

    await drive_cycle(dut, shadow, ST_IDLE)


@cocotb.test()
async def coef_ready_is_purely_combinational(dut):
    """htp/decompress ready track state && valid with no reset dependency.

    The RTL assigns are plain `assign` statements, so ready can be asserted
    even while rst_n is low -- that is intentional hardware behaviour, not a
    testbench bug, and is worth pinning down explicitly.
    """
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.htp_coef.value = 0
    dut.decompress_coef.value = 0
    dut.r_coef.value = 0

    dut.state.value = ST_HTP
    dut.htp_coef_valid.value = 1
    dut.decompress_coef_valid.value = 0
    await Timer(1, "ns")
    assert int(dut.htp_coef_ready.value) == 1
    assert int(dut.decompress_coef_ready.value) == 0

    dut.state.value = ST_DECOMPRESS
    dut.htp_coef_valid.value = 0
    dut.decompress_coef_valid.value = 1
    await Timer(1, "ns")
    assert int(dut.htp_coef_ready.value) == 0
    assert int(dut.decompress_coef_ready.value) == 1

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def full_htp_transfer_writes_expected_polynomial(dut):
    """Stream exactly N htp coefficients and check the write sequence.

    Per the RTL, `done` only pulses once i_counter has already reached N,
    which requires one further valid beat after the N-th coefficient -- that
    extra beat is deliberately included below rather than assumed away.
    """
    await reset_dut(dut)
    shadow = ShadowState(n=N)
    writes: list[tuple[int, int]] = []

    coefficients = [random.randint(0, COEF_MASK) for _ in range(N)]

    for coef in coefficients:
        await drive_cycle(dut, shadow, ST_HTP, htp_coef=coef, htp_valid=1, writes=writes)

    assert int(dut.done.value) == 0
    assert shadow.i_counter == N

    # One extra valid beat is required to observe the done pulse.
    await drive_cycle(dut, shadow, ST_HTP, htp_coef=0, htp_valid=1, writes=writes)
    assert shadow.i_counter == 0  # wrapped back to 0 the cycle after done pulsed

    await drive_cycle(dut, shadow, ST_IDLE)

    written = {addr: data for addr, data in writes if (addr >> 10) == HTP_TAG and (addr & 0x3FF) < N}
    for index, coef in enumerate(coefficients):
        assert written[(HTP_TAG << 10) | index] == coef


@cocotb.test()
async def full_decompress_transfer_writes_expected_polynomial(dut):
    """Same as the htp case, but for the decompress channel (addr tag 1)."""
    await reset_dut(dut)
    shadow = ShadowState(n=N)
    writes: list[tuple[int, int]] = []

    coefficients = [random.randint(0, COEF_MASK) for _ in range(N)]

    for coef in coefficients:
        await drive_cycle(
            dut, shadow, ST_DECOMPRESS, decompress_coef=coef, decompress_valid=1, writes=writes
        )

    await drive_cycle(
        dut, shadow, ST_DECOMPRESS, decompress_coef=0, decompress_valid=1, writes=writes
    )
    assert shadow.i_counter == 0

    written = {
        addr: data for addr, data in writes if (addr >> 10) == DECOMPRESS_TAG and (addr & 0x3FF) < N
    }
    for index, coef in enumerate(coefficients):
        assert written[(DECOMPRESS_TAG << 10) | index] == coef


@cocotb.test()
async def bubbles_in_valid_do_not_advance_the_counter(dut):
    """Random idle cycles (valid low) must not move i_counter forward, and the
    final polynomial written must still match the input once all N
    coefficients have actually been accepted."""
    await reset_dut(dut)
    shadow = ShadowState(n=N)
    writes: list[tuple[int, int]] = []

    coefficients = [random.randint(0, COEF_MASK) for _ in range(N)]

    for coef in coefficients:
        counter_before_bubbles = shadow.i_counter
        for _ in range(random.randint(0, 2)):
            await drive_cycle(dut, shadow, ST_HTP, htp_coef=coef, htp_valid=0, writes=writes)
            assert shadow.i_counter == counter_before_bubbles
        await drive_cycle(dut, shadow, ST_HTP, htp_coef=coef, htp_valid=1, writes=writes)

    assert shadow.i_counter == N

    # One more cycle is needed to flush the last coefficient's registered
    # write (poly_addr/w_coef/en) into `writes`, same as the full-transfer test.
    await drive_cycle(dut, shadow, ST_HTP, htp_coef=0, htp_valid=1, writes=writes)

    written = {addr: data for addr, data in writes if (addr >> 10) == HTP_TAG and (addr & 0x3FF) < N}
    for index, coef in enumerate(coefficients):
        assert written[(HTP_TAG << 10) | index] == coef


@cocotb.test()
async def idle_state_holds_registered_outputs(dut):
    """Returning to IDLE mid-stream must freeze poly_addr/w_coef/en/i_counter."""
    await reset_dut(dut)
    shadow = ShadowState(n=N)

    halfway = max(1, N // 2)
    for _ in range(halfway):
        coef = random.randint(0, COEF_MASK)
        await drive_cycle(dut, shadow, ST_HTP, htp_coef=coef, htp_valid=1)

    frozen_addr, frozen_data, frozen_en, frozen_counter = (
        shadow.poly_addr,
        shadow.w_coef,
        shadow.en,
        shadow.i_counter,
    )

    for _ in range(5):
        await drive_cycle(dut, shadow, ST_IDLE, htp_coef=random.randint(0, COEF_MASK), htp_valid=1)
        assert shadow.poly_addr == frozen_addr
        assert shadow.w_coef == frozen_data
        assert shadow.en == frozen_en
        assert shadow.i_counter == frozen_counter


@cocotb.test()
async def reset_mid_transfer_clears_registers_immediately(dut):
    """Asserting rst_n mid-stream must asynchronously clear all registers."""
    await reset_dut(dut)
    shadow = ShadowState(n=N)

    for _ in range(max(1, N // 2)):
        await drive_cycle(dut, shadow, ST_HTP, htp_coef=random.randint(0, COEF_MASK), htp_valid=1)

    assert shadow.i_counter > 0

    dut.rst_n.value = 0
    await Timer(1, "ns")
    assert int(dut.en.value) == 0
    assert int(dut.poly_addr.value) == 0
    assert int(dut.w_coef.value) == 0

    # Drop the in-flight transfer before releasing reset, otherwise the still
    # asserted htp_coef_valid/state would latch one more (stale) transfer on
    # the very edge that lifts rst_n.
    dut.state.value = ST_IDLE
    dut.htp_coef_valid.value = 0
    dut.decompress_coef_valid.value = 0

    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    shadow.reset()

    await drive_cycle(dut, shadow, ST_IDLE)


@cocotb.test()
async def random_stress_matches_shadow_model(dut):
    """Randomly toggle state/valid/coef every cycle for many cycles and check
    the DUT tracks the shadow register model exactly, including transitions
    between htp, decompress, idle and an unused state encoding."""
    await reset_dut(dut)
    shadow = ShadowState(n=N)

    states = [ST_IDLE, ST_HTP, ST_DECOMPRESS, ST_UNUSED]
    for _ in range(300):
        state = random.choice(states)
        await drive_cycle(
            dut,
            shadow,
            state,
            htp_coef=random.randint(0, COEF_MASK),
            htp_valid=random.randint(0, 1),
            decompress_coef=random.randint(0, COEF_MASK),
            decompress_valid=random.randint(0, 1),
        )


def test_poly_accessor_runner() -> None:
    """Build and run the Poly_Accessor cocotb tests."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path.parent.parent / "Verilog" / "falcon_pkg.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Poly_Accessor.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Poly_Accessor",
        parameters={"N": N},
        always=True,
    )
    runner.test(hdl_toplevel="Poly_Accessor", test_module="test_poly_accessor")


if __name__ == "__main__":
    test_poly_accessor_runner()
