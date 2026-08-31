from ntt_constants import roots_dict_Zq, inv_mod_q

q = 12 * 1024 + 1

def split(f):
    """Split a polynomial f in two polynomials.

    Args:
        f: a polynomial

    Format: coefficient
    """
    n = len(f)
    f0 = [f[2 * i + 0] for i in range(n // 2)]
    f1 = [f[2 * i + 1] for i in range(n // 2)]
    return [f0, f1]

def merge(f_list):
    """Merge two polynomials into a single polynomial f.

    Args:
        f_list: a list of polynomials

    Format: coefficient
    """
    f0, f1 = f_list
    n = 2 * len(f0)
    f = [0] * n
    for i in range(n // 2):
        f[2 * i + 0] = f0[i]
        f[2 * i + 1] = f1[i]
    return f

"""i2 is the inverse of 2 mod q."""
i2 = 6145


""" sqr1 is a square root of (-1) mod q (currently, sqr1 = 1479)."""
sqr1 = roots_dict_Zq[2][0]


def split_ntt(f_ntt):
    """Split a polynomial f in two or three polynomials.

    Args:
        f_ntt: a polynomial

    Format: NTT
    """
    n = len(f_ntt)
    w = roots_dict_Zq[n]
    f0_ntt = [0] * (n // 2)
    f1_ntt = [0] * (n // 2)
    for i in range(n // 2):
        f0_ntt[i] = (i2 * (f_ntt[2 * i] + f_ntt[2 * i + 1])) % q
        f1_ntt[i] = (i2 * (f_ntt[2 * i] - f_ntt[2 * i + 1]) * inv_mod_q[w[2 * i]]) % q
    return [f0_ntt, f1_ntt]


def merge_ntt(f_list_ntt):
    """Merge two or three polynomials into a single polynomial f.

    Args:
        f_list_ntt: a list of polynomials

    Format: NTT
    """
    f0_ntt, f1_ntt = f_list_ntt
    n = 2 * len(f0_ntt)
    w = roots_dict_Zq[n]
    f_ntt = [0] * n
    for i in range(n // 2):
        f_ntt[2 * i + 0] = (f0_ntt[i] + w[2 * i] * f1_ntt[i]) % q
        f_ntt[2 * i + 1] = (f0_ntt[i] - w[2 * i] * f1_ntt[i]) % q
    return f_ntt


def ntt(f):
    """Compute the NTT of a polynomial.

    Args:
        f: a polynomial

    Format: input as coefficients, output as NTT
    """
    n = len(f)
    if (n > 2):
        f0, f1 = split(f)
        f0_ntt = ntt(f0)
        f1_ntt = ntt(f1)
        f_ntt = merge_ntt([f0_ntt, f1_ntt])
    elif (n == 2):
        f_ntt = [0] * n
        f_ntt[0] = (f[0] + sqr1 * f[1]) % q
        f_ntt[1] = (f[0] - sqr1 * f[1]) % q
    return f_ntt


def intt(f_ntt):
    """Compute the inverse NTT of a polynomial.

    Args:
        f_ntt: a NTT of a polynomial

    Format: input as NTT, output as coefficients
    """
    n = len(f_ntt)
    if (n > 2):
        f0_ntt, f1_ntt = split_ntt(f_ntt)
        f0 = intt(f0_ntt)
        f1 = intt(f1_ntt)
        f = merge([f0, f1])
    elif (n == 2):
        f = [0] * n
        f[0] = (i2 * (f_ntt[0] + f_ntt[1])) % q
        f[1] = (i2 * inv_mod_q[sqr1] * (f_ntt[0] - f_ntt[1])) % q
    return f


def mul_zq(f, g):
    """Multiplication of two polynomials (coefficient representation)."""
    return intt(mul_ntt(ntt(f), ntt(g)))


def div_zq(f, g):
    """Division of two polynomials (coefficient representation)."""
    try:
        return intt(div_ntt(ntt(f), ntt(g)))
    except ZeroDivisionError:
        raise


# def adj(f):
#     """Ajoint of a polynomial (coefficient representation)."""
#     return intt(adj_ntt(ntt(f)))


def mul_ntt(f_ntt, g_ntt):
    """Multiplication of two polynomials (coefficient representation)."""
    assert len(f_ntt) == len(g_ntt)
    deg = len(f_ntt)
    return [(f_ntt[i] * g_ntt[i]) % q for i in range(deg)]


"""This value is the ratio between:
    - The degree n
    - The number of complex coefficients of the NTT
While here this ratio is 1, it is possible to develop a short NTT such that it is 2.
"""
ntt_ratio = 1