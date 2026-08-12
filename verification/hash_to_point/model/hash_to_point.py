# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0
from __future__ import annotations

from Crypto.Hash import SHAKE256


def hash_to_point(message: bytes, sec_lv: int = 0) -> list[int]:
    """Reference SHAKE256 hash-to-point implementation for the HashToPoint module."""
    q = 12289
    k = 5
    n = 512 if sec_lv == 0 else 1024

    shake = SHAKE256.new()
    shake.update(message)

    coeffs: list[int] = []
    while len(coeffs) < n:
        twobytes = shake.read(2)
        if len(twobytes) < 2:
            raise ValueError("SHAKE output too short")

        elt = (twobytes[0] << 8) + twobytes[1]
        if elt < k * q:
            coeffs.append(elt % q)

    return coeffs
