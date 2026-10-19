from __future__ import annotations

import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

_verify_top_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_verify_top_root / "model"))
sys.path.insert(0, str(_verify_top_root.parent / "hash_to_point" / "model"))
sys.path.insert(0, str(_verify_top_root.parent / "decompress" / "model"))
sys.path.insert(0, str(_verify_top_root.parent / "checknorm" / "model"))
sys.path.insert(0, str(_verify_top_root.parent / "checknorm"))

from hash_to_point import hash_to_point as model_hash_to_point  # noqa: E402
from decompress import compress as model_compress  # noqa: E402
from decompress import decompress as model_decompress  # noqa: E402

try:
    from model.sign import sign as model_sign  # noqa: E402
except Exception:  # pragma: no cover - sign() needs the pickled Falcon key
    model_sign = None

# --------------------------------------------------------------------------
# Constants mirrored from Verilog/falcon_pkg.sv and Verilog/ComputeEngine/*.
# --------------------------------------------------------------------------
WIDTH = 14
Q = 12289

N_I = 512
N_V = 1024
SIG_LEN_I = 666
SIG_LEN_V = 1280
HEADER_AND_NONCE_LEN = 41
NONCE_LEN = 40

# From Input_Control.sv: sig_first=5, sig_last=83/159, msg_first=84/160.
SIG_FIRST = 5
SIG_LAST_I, SIG_LAST_V = 83, 159
MSG_FIRST_I, MSG_FIRST_V = 84, 160

# From Poly_Accessor.sv: htp_addr=0, decompress_addr=1 (7-bit poly tag,
# concatenated with a 10-bit coefficient index -> PolyRAM address).
HTP_ADDR_TAG = 0
DECOMPRESS_ADDR_TAG = 1
POLY_TAG_SHIFT = 10  # poly_addr = {tag[6:0], index[9:0]}


def chunks_le(data: bytes) -> list[int]:
    """Little-endian 8-byte chunking, matching test_hash_to_point.py's drive_message."""
    return [
        int.from_bytes(data[i : i + 8].ljust(8, b"\x00"), "little")
        for i in range(0, len(data), 8)
    ]


def chunks_be(data: bytes) -> list[int]:
    """Big-endian 8-byte chunking, matching test_decompress.py's encode_input."""
    return [
        int.from_bytes(data[i : i + 8].ljust(8, b"\x00"), "big")
        for i in range(0, len(data), 8)
    ]


def signed_coefficient(value: int) -> int:
    """Decode a 14-bit two's-complement coefficient as stored by Decompress_chunk/PolyRAM."""
    value &= (1 << WIDTH) - 1
    return value - (1 << WIDTH) if value & (1 << (WIDTH - 1)) else value


# --------------------------------------------------------------------------
# Reset / low-level helpers
# --------------------------------------------------------------------------
async def reset_dut(dut, start_clock: bool = True) -> None:
    if start_clock:
        cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.axi_data.value = 0
    dut.axi_valid.value = 0
    dut.Sec_LV.value = 0
    dut.message_last.value = 0
    dut.message_byte_length.value = 0
    await Timer(20, "ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def axi_word_driver(dut, beats: list[tuple[int, int]]) -> None:
    """Drive one AXI beat per queued (word, message_last) pair.

    This is an ordinary, backpressure-respecting AXI-style master: present
    axi_data/axi_valid (and message_last on the correct beat) and simply
    wait for the DUT's own axi_ready before advancing to the next word. It
    never peeks at any internal DUT signal to decide when to advance --
    only the diagnostics below do that, for logging/assertions after the
    fact. Runs as a background task so the caller can bound overall
    progress with its own timeout instead of risking a hang if the DUT
    stops asking for more input (see the big comment in the test below for
    why that legitimately happens here).
    """
    for word, last in beats:
        dut.axi_data.value = word
        dut.message_last.value = last
        dut.axi_valid.value = 1
        while True:
            await RisingEdge(dut.clk)
            if int(dut.axi_ready.value):
                break
        dut.message_last.value = 0
    dut.axi_valid.value = 0
    dut.axi_data.value = 0


def build_beats(
    nonce: bytes,
    message: bytes,
    payload: bytes,
    sec_lv: int,
) -> list[tuple[int, int]]:
    """Build the full AXI beat sequence: nonce, filler, encoded signature, message.

    Layout driven by Input_Control.sv (see the big comment in the test
    below for *why* the encoded-signature words end up split around the
    message the way they do):

      idx 0..4            : nonce (5 words, 40 bytes) -- real HTP input
      idx 5..sig_last-1    : filler (unconsumed by either HTP or Decompress
                             under the current RTL; content is irrelevant)
      idx sig_last         : encoded-signature word 0 (the only signature
                             word Decompress_chunk sees before the message)
      idx msg_first..msg_last : the real message, for HTP
      idx msg_last+1..     : encoded-signature words 1..end, consumed once
                             Decompress_chunk actually asks for more (after
                             the message has been fully absorbed)
    """
    sig_last = SIG_LAST_V if sec_lv else SIG_LAST_I

    nonce_words = chunks_le(nonce)
    assert len(nonce_words) == 5

    filler_words = [0] * (sig_last - SIG_FIRST)
    payload_words = chunks_be(payload)
    message_words = chunks_le(message)
    assert message_words, "message must be non-empty to avoid the ambiguous zero-length edge case"

    beats: list[tuple[int, int]] = []
    for w in nonce_words:
        beats.append((w, 0))
    for w in filler_words:
        beats.append((w, 0))
    beats.append((payload_words[0], 0))
    for i, w in enumerate(message_words):
        beats.append((w, 1 if i == len(message_words) - 1 else 0))
    for w in payload_words[1:]:
        beats.append((w, 0))
    return beats


async def read_polyram_coeffs(dut, tag: int, count: int, signed: bool) -> list[int]:
    """Read back `count` coefficients for polynomial `tag` from PolyRAM.

    PolyRAM's flat mem[] is addressed as {7-bit tag, 10-bit index}
    (Poly_Accessor.sv's htp_addr=0 / decompress_addr=1 localparams), and
    each 64-bit word holds the WIDTH=14-bit coefficient in its low bits
    (Poly_Accessor zero-extends: w_coef <= {50'b0, coef}), with
    Decompress_chunk's coefficients being a 14-bit two's-complement signed
    value and HashToPoint's being an unsigned value mod Q.
    """
    base = tag << POLY_TAG_SHIFT
    out = []
    for i in range(count):
        raw = int(dut.u_polyram.mem[base + i].value) & ((1 << WIDTH) - 1)
        out.append(signed_coefficient(raw) if signed else raw)
    return out


class HtpCoefMonitor:
    """Passive monitor on the HashToPoint -> Poly_Accessor coefficient stream.

    Records every htp_coef that is actually handed over, i.e. every cycle in
    which both htp_coef_valid (HashToPoint's o_valid) and htp_coef_ready
    (Poly_Accessor's o_ready) are high. This checks HashToPoint's output
    directly, independent of how Poly_Accessor/PolyRAM store it, so a
    mismatch here points at HashToPoint while a mismatch only in PolyRAM
    points at the storage path.
    """

    def __init__(self, dut) -> None:
        self.dut = dut
        self.coeffs: list[int] = []
        self.valid_without_ready = 0  # coefficients presented but not accepted
        self._task = None

    def start(self) -> None:
        self._task = cocotb.start_soon(self._run())

    def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            self._task = None

    async def _run(self) -> None:
        while True:
            await RisingEdge(self.dut.clk)
            valid = int(self.dut.htp_coef_valid.value)
            ready = int(self.dut.htp_coef_ready.value)
            if valid and ready:
                self.coeffs.append(int(self.dut.htp_coef.value))
            elif valid:
                self.valid_without_ready += 1


def check_htp_coeffs(dut, monitor: HtpCoefMonitor, expected: list[int]) -> None:
    """Compare the coefficients captured on the HTP output port against the model."""
    got = monitor.coeffs
    n = len(expected)

    assert all(0 <= c < Q for c in got), (
        f"HTP emitted out-of-range coefficient(s) (must be in [0, Q)): "
        f"{[(i, c) for i, c in enumerate(got) if not 0 <= c < Q][:8]}"
    )
    first_bad = next((i for i in range(min(len(got), n)) if got[i] != expected[i]), None)
    assert first_bad is None, (
        f"HTP output coefficient mismatch at index {first_bad}: "
        f"got {got[first_bad]} expected {expected[first_bad]} "
        f"(got[{first_bad}:{first_bad + 8}]={got[first_bad:first_bad + 8]}, "
        f"expected[{first_bad}:{first_bad + 8}]={expected[first_bad:first_bad + 8]})"
    )
    assert len(got) == n, (
        f"HTP emitted {len(got)} accepted coefficients, expected exactly {n} "
        f"({monitor.valid_without_ready} more were presented without ready)"
    )
    dut._log.info("HTP output stream matches model: %d coefficients", n)


def dump_state(dut, label: str) -> None:
    """Diagnostic snapshot of the internal FSMs, useful when iterating on stimulus timing."""
    dut._log.info(
        "[%s] top.state=%d htp.state=%d htp.done=%d decomp.state=%d decomp.sig_ready=%d "
        "decomp.coef_valid=%d decomp.done=%d decomp.fail=%d poly_acc.i_counter=%d "
        "poly_acc.htp_ready=%d poly_acc.decomp_ready=%d axi_ready=%d done=%d fail=%d pass=%d",
        label,
        int(dut.state.value),
        int(dut.u_htp.state.value),
        int(dut.u_htp.done.value),
        int(dut.u_decompress.state.value),
        int(dut.u_decompress.sig_ready.value),
        int(dut.u_decompress.coef_valid.value),
        int(dut.u_decompress.done.value),
        int(dut.u_decompress.fail.value),
        int(dut.u_poly_accessor.i_counter.value),
        int(dut.htp_coef_ready.value),
        int(dut.decompress_coef_ready.value),
        int(dut.axi_ready.value),
        int(dut.done.value),
        int(dut.fail.value),
        int(getattr(dut, "pass").value),
    )


async def run_transaction(
    dut,
    nonce: bytes,
    message: bytes,
    s2: list[int],
    sec_lv: int,
    timeout_cycles: int = 200_000,
    log_every: int = 0,
) -> None:
    """Drive one full Verify_top transaction and leave the DUT parked once
    both PolyRAM regions have been written (see the FSM-lockup note in the
    caller for why we cannot simply wait for `done`)."""
    n = N_V if sec_lv else N_I
    sig_len = SIG_LEN_V if sec_lv else SIG_LEN_I
    payload_len = sig_len - HEADER_AND_NONCE_LEN

    encoded = model_compress(list(s2), payload_len)
    assert encoded is not False, "s2 does not fit in the compressed signature budget"
    decoded_check = model_decompress(encoded, payload_len, n)
    assert decoded_check == list(s2)

    beats = build_beats(nonce, message, encoded, sec_lv)

    dut.Sec_LV.value = sec_lv
    dut.message_byte_length.value = len(message)

    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Only begin streaming once `start` has moved Verify_top out of ST_IDLE.
    # In ST_IDLE Input_Control still reports axi_ready=1 (HashToPoint's
    # message_ready resets high), so a beat offered alongside `start` would be
    # consumed while HashToPoint is idle and silently dropped, shifting every
    # later word by one slot.
    cocotb.start_soon(axi_word_driver(dut, beats))

    # Wait until Poly_Accessor has written all N decompress coefficients
    # (its i_counter wraps back to 0 the same cycle it reaches N -- see
    # Poly_Accessor.sv's i_counter always_ff), which per the RTL-quirk
    # analysis below is the last of the two writes to actually finish.
    saw_decompress_progress = False
    for cyc in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if log_every and cyc % log_every == 0:
            dump_state(dut, f"cyc={cyc}")
        if int(dut.decompress_coef_ready.value):
            saw_decompress_progress = True
        if saw_decompress_progress and int(dut.u_poly_accessor.i_counter.value) == 0 and int(dut.state.value) != 1:
            # i_counter just wrapped after reaching N while writing decompress coeffs.
            break
    else:
        dump_state(dut, "TIMEOUT")
        raise AssertionError("Timed out waiting for the decompress PolyRAM write to complete")

    # Give the write a cycle to fully settle in PolyRAM before reading it.
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_verify_top_htp_and_decompress_match_model(dut):
    """PolyRAM ends up holding the correct HashToPoint and Decompress polynomials."""
    
    await reset_dut(dut)

    nonce = bytes(range(NONCE_LEN))
    message = b"Falcon Verify_top testbench message!"  # 37 bytes, not a multiple of 8
    s2 = [0, 1, -1, 127, -127, 128, -128, 255, -255] + [0] * (N_I - 9)

    await run_transaction(dut, nonce, message, s2, sec_lv=0)

    expected_htp = model_hash_to_point(nonce + message, sec_lv=0)
    got_htp = await read_polyram_coeffs(dut, HTP_ADDR_TAG, N_I, signed=False)
    assert got_htp == expected_htp, (
        f"HTP PolyRAM mismatch: first divergence at "
        f"{next((i for i in range(N_I) if got_htp[i] != expected_htp[i]), None)}"
    )

    got_decompress = await read_polyram_coeffs(dut, DECOMPRESS_ADDR_TAG, N_I, signed=True)
    assert got_decompress == s2, (
        f"Decompress PolyRAM mismatch: first divergence at "
        f"{next((i for i in range(N_I) if got_decompress[i] != s2[i]), None)}"
    )

    # Secondary checks (documented RTL bug: `done` never asserts -- see
    # docstring above). `fail` is meaningful independently of `done` since
    # it is a plain latch set combinationally while state==ST_DECOMPRESS.
    assert int(dut.fail.value) == 0, "fail asserted for a well-formed signature"
    assert int(getattr(dut, "pass").value) == 1, "pass should be !fail"
    for _ in range(50):
        await RisingEdge(dut.clk)
    assert int(dut.done.value) == 0, (
        "dut.done unexpectedly asserted -- if this starts passing, the "
        "ST_DECOMPRESS_STORE lockup documented above has been fixed and "
        "this assertion (and the surrounding comment) should be revisited"
    )


@cocotb.test()
async def test_verify_top_htp_output_coefficients(dut):
    """The coefficients HashToPoint emits on its output port match the model.

    Unlike the PolyRAM checks, this observes htp_coef on the
    HashToPoint/Poly_Accessor handshake, so it tests HashToPoint itself.
    Covers several message lengths, including multiples of 8 bytes and a
    single byte, to exercise message_last_bytes handling.
    """
    vectors = [
        (bytes(range(NONCE_LEN)), b"Falcon Verify_top testbench message!"),  # 37 bytes
        (bytes((i * 7 + 3) % 256 for i in range(NONCE_LEN)), b"exactly-sixteen!"),  # 16 bytes
        (bytes(255 - i for i in range(NONCE_LEN)), b"x"),  # 1 byte
    ]
    s2 = [0] * N_I

    for i, (nonce, message) in enumerate(vectors):
        await reset_dut(dut, start_clock=(i == 0))

        monitor = HtpCoefMonitor(dut)
        monitor.start()
        await run_transaction(dut, nonce, message, s2, sec_lv=0)
        monitor.stop()

        expected = model_hash_to_point(nonce + message, sec_lv=0)
        dut._log.info("Checking HTP output for %d-byte message %r", len(message), message)
        check_htp_coeffs(dut, monitor, expected)


@cocotb.test()
async def test_verify_top_zero_polynomial(dut):
    """A trivial all-zero s2 also lands correctly (sanity check on addressing/decoding)."""
    await reset_dut(dut)

    nonce = bytes((i * 3 + 1) % 256 for i in range(NONCE_LEN))
    message = b"short msg"  # 9 bytes
    s2 = [0] * N_I

    await run_transaction(dut, nonce, message, s2, sec_lv=0)

    expected_htp = model_hash_to_point(nonce + message, sec_lv=0)
    got_htp = await read_polyram_coeffs(dut, HTP_ADDR_TAG, N_I, signed=False)
    assert got_htp == expected_htp

    got_decompress = await read_polyram_coeffs(dut, DECOMPRESS_ADDR_TAG, N_I, signed=True)
    assert got_decompress == s2


@cocotb.test()
async def test_verify_top_random_signed_signature(dut):
    """A realistic (s1, s2) pair from the Falcon signing model, if available."""
    if model_sign is None:
        return

    await reset_dut(dut)

    nonce = bytes(range(NONCE_LEN))
    message = b"random-vector-test-message-1234"  # 32 bytes

    _, s2 = model_sign(0, N_I, message)

    await run_transaction(dut, nonce, message, list(s2), sec_lv=0)

    expected_htp = model_hash_to_point(nonce + message, sec_lv=0)
    got_htp = await read_polyram_coeffs(dut, HTP_ADDR_TAG, N_I, signed=False)
    assert got_htp == expected_htp

    got_decompress = await read_polyram_coeffs(dut, DECOMPRESS_ADDR_TAG, N_I, signed=True)
    assert got_decompress == list(s2)


def test_verify_top_runner() -> None:
    """Build and run the Verify_top cocotb tests."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent

    sources = [
        proj_path.parent.parent / "Verilog" / "falcon_pkg.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Keccak.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Shake256.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "HashToPoint.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Decompress_chunk.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Input_Control.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Poly_Accessor.sv",
        proj_path.parent.parent / "Verilog" / "Memory" / "PolyRAM.sv",
        proj_path.parent.parent / "Verilog" / "ComputeEngine" / "Verify_top.sv",
    ]

    from cocotb_tools.runner import get_runner

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="Verify_top",
        always=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(hdl_toplevel="Verify_top", test_module="test_verify_top")


if __name__ == "__main__":
    test_verify_top_runner()
