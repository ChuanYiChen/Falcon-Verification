# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0
from __future__ import annotations

#from Crypto.Hash import SHAKE256


def decompress(sig: bytes, sec_lv: int = 0) -> list[int]:
    """Reference decompression implementation for the Decompress module."""""
    q = 12289
    n = 512 if sec_lv == 0 else 1024

    coeffs: list[int] = []
    while len(coeffs) < n:
        s_prime = sum(sig[7-i] << i for i in range(7))
        k = 0
        while (sig[8+k] == 0):
            k += 1
        if (sig[0] == 0):
            coeffs.append(s_prime + (k << 7))
        else:
            if ((s_prime + (k << 7)) != 0):
                coeffs.append(q - (s_prime + (k << 7)))
        sig = sig[8+k+1:]
    if (sig != 0):
        raise ValueError("Decompression failed: extra bytes remaining")
    return coeffs
