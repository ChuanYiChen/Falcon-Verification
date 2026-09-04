from os import urandom
from Crypto.Hash import SHAKE256
import pickle
from pathlib import Path

from common import q
from fft import fft, ifft, sub, neg, add_fft, mul_fft
from ffsampling import ffsampling_fft
from rng import ChaCha20

logn = {
    2: 1,
    4: 2,
    8: 3,
    16: 4,
    32: 5,
    64: 6,
    128: 7,
    256: 8,
    512: 9,
    1024: 10
}

def hash_to_point(message: bytes, n: int, salt: bytes) -> list[int]:
    """
    Hash a message to a point in Z[x] mod(Phi, q).
    Inspired by the Parse function from NewHope.
    """
    if q > (1 << 16):
        raise ValueError("The modulus is too large")

    k = (1 << 16) // q
    # Create a SHAKE object and hash the salt and message.
    shake = SHAKE256.new()
    shake.update(salt)
    shake.update(message)
    # Output pseudorandom bytes and map them to coefficients.
    hashed = [0 for i in range(n)]
    i = 0
    while i < n:
        # Takes 2 bytes, transform them in a 16 bits integer
        twobytes = shake.read(2)
        elt = (twobytes[0] << 8) + twobytes[1]  # This breaks in Python 2.x
        # Implicit rejection sampling
        if elt < k * q:
            hashed[i] = elt % q
            i += 1
    return hashed

def sample_preimage(B0_fft, T_fft, n: int, sigmin, point, seed=None):
    """
    Sample a short vector s such that s[0] + s[1] * h = point.
    """
    [[a, b], [c, d]] = B0_fft

    # We compute a vector t_fft such that:
    #     (fft(point), fft(0)) * B0_fft = t_fft
    # Because fft(0) = 0 and the inverse of B has a very specific form,
    # we can do several optimizations.
    point_fft = fft(point)
    t0_fft = [(point_fft[i] * d[i]) / q for i in range(n)]
    t1_fft = [(-point_fft[i] * b[i]) / q for i in range(n)]
    t_fft = [t0_fft, t1_fft]

    # We now compute v such that:
    #     v = z * B0 for an integral vector z
    #     v is close to (point, 0)
    if seed is None:
        # If no seed is defined, use urandom as the pseudo-random source.
        z_fft = ffsampling_fft(t_fft, T_fft, sigmin, urandom)
    else:
        # If a seed is defined, initialize a ChaCha20 PRG
        # that is used to generate pseudo-randomness.
        chacha_prng = ChaCha20(seed)
        z_fft = ffsampling_fft(t_fft, T_fft, sigmin,
                                chacha_prng.randombytes)

    v0_fft = add_fft(mul_fft(z_fft[0], a), mul_fft(z_fft[1], c))
    v1_fft = add_fft(mul_fft(z_fft[0], b), mul_fft(z_fft[1], d))
    v0 = [int(round(elt)) for elt in ifft(v0_fft)]
    v1 = [int(round(elt)) for elt in ifft(v1_fft)]

    # The difference s = (point, 0) - v is such that:
    #     s is short
    #     s[0] + s[1] * h = point
    s = [sub(point, v0), neg(v1)]
    return s

def sign(sk, n: int, message: bytes, randombytes=urandom):
    """
    Sign a message. The message MUST be a byte string or byte array.
    Optionally, one can select the source of (pseudo-)randomness used
    (default: urandom).
    """
    with open(Path(__file__).with_name("falcon_sk.pkl"), "rb") as file:
        sk = pickle.load(file)

    (f, g, F, G, B0_fft, T_fft) = sk

    salt = randombytes(40)
    hashed = hash_to_point(message, n, salt)

    if n == 512:
        sigmin = sigmin=1.2778336969128337
        sig_bound = 34034726
    elif n == 1024:
        sigmin=1.298280334344292
        sig_bound = 70265242

    # We repeat the signing procedure until we find a signature that is
    # short enough (both the Euclidean norm and the bytelength)
    while (1):
        if (randombytes == urandom):
            s = sample_preimage(B0_fft, T_fft, n=n, sigmin=sigmin, point=hashed)
        else:
            seed = randombytes(56)
            s = sample_preimage(B0_fft, T_fft, n=n, sigmin=sigmin, point=hashed, seed=seed)
        norm_sign = sum(coef ** 2 for coef in s[0])
        norm_sign += sum(coef ** 2 for coef in s[1])
        # Check the Euclidean norm
        if norm_sign <= sig_bound:
            return s