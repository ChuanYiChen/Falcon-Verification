"""Reference Keccak-f[1600] permutation (pure Python, 64-bit lanes).
"""
from typing import List

MASK64 = (1 << 64) - 1

ROTC = [
    0, 1, 62, 28, 27,
    36, 44, 6, 55, 20,
    3, 10, 43, 25, 39,
    41, 45, 15, 21, 8,
    18, 2, 61, 56, 14,
]

ROUND_CONSTANTS = [
    0x0000000000000001,
    0x0000000000008082,
    0x800000000000808A,
    0x8000000080008000,
    0x000000000000808B,
    0x0000000080000001,
    0x8000000080008081,
    0x8000000000008009,
    0x000000000000008A,
    0x0000000000000088,
    0x0000000080008009,
    0x000000008000000A,
    0x000000008000808B,
    0x800000000000008B,
    0x8000000000008089,
    0x8000000000008003,
    0x8000000000008002,
    0x8000000000000080,
    0x000000000000800A,
    0x800000008000000A,
    0x8000000080008081,
    0x8000000000008080,
    0x0000000080000001,
    0x8000000080008008,
]


def rotl64(x: int, n: int) -> int:
    n %= 64
    if n == 0:
        return x & MASK64
    return ((x << n) & MASK64) | ((x & MASK64) >> (64 - n))


def keccak_f1600(state_in: List[int]) -> List[int]:
    """Apply the Keccak-f[1600] permutation to a 25-word state.

    state_in: list of 25 64-bit integers (lane order as in Keccak.sv)
    returns: list of 25 64-bit integers
    """
    if len(state_in) != 25:
        raise ValueError("state must be 25 lanes")

    a = [x & MASK64 for x in state_in]

    for rnd_idx, rc in enumerate(ROUND_CONSTANTS):
        # Theta
        c = [a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] for x in range(5)]
        d = [ (c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1)) & MASK64 for x in range(5)]

        # Rho and Pi
        b = [0] * 25
        for x in range(5):
            for y in range(5):
                src_idx = x + 5 * y
                dst_idx = y + 5 * ((2 * x + 3 * y) % 5)
                v = (a[src_idx] ^ d[x]) & MASK64
                r = ROTC[src_idx]
                if r == 0:
                    b[dst_idx] = v
                else:
                    b[dst_idx] = rotl64(v, r)

        # Chi
        for x in range(5):
            for y in range(5):
                idx = x + 5 * y
                a[idx] = (b[idx] ^ ((~b[((x + 1) % 5) + 5 * y] & MASK64) & b[((x + 2) % 5) + 5 * y])) & MASK64

        # Iota
        a[0] = (a[0] ^ rc) & MASK64

    return a


if __name__ == "__main__":
    # quick smoke test: all-zero state
    s = [0] * 25
    out = keccak_f1600(s)
    print(out)
