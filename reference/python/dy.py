"""Bounded Dolev-Yao term algebra and derivability.

Foundation for the minimal-trust tool. Terms are immutable tuples. Derivability is the
adversary's deductive closure, computed over a finite term universe (the subterms of the
messages in play), which keeps it terminating and decidable -- the standard bounded approach.

Keys:
  ('name', s)            an atom (principal name, nonce, constant, or a key handle)
Key handles are atoms with conventional names; inverse() knows the pairing:
  pk_X  <-> sk_X   (public / private)
  k_XY  self-inverse (symmetric shared key)

Constructors:
  ('pair', a, b)         pairing
  ('enc',  key, msg)     encryption under key (symmetric or public); needs inverse(key) to open
  ('sig',  key, msg)     signature by key; the message is readable, but producing it needs key
"""

from itertools import product


# ---- constructors -----------------------------------------------------------

def name(s):            return ('name', s)
def pair(a, b):         return ('pair', a, b)
def enc(key, msg):      return ('enc', key, msg)
def sig(key, msg):      return ('sig', key, msg)


def inverse(k):
    """Decryption/verification key inverse. sk<->pk; symmetric keys self-inverse."""
    if k[0] == 'name':
        s = k[1]
        if s.startswith('pk_'):
            return name('sk_' + s[3:])
        if s.startswith('sk_'):
            return name('pk_' + s[3:])
    return k  # symmetric or unknown: self-inverse


# ---- subterms and universe --------------------------------------------------

def subterms(t, acc=None):
    """All subterms of t, including t itself."""
    if acc is None:
        acc = set()
    acc.add(t)
    if t[0] in ('pair', 'enc', 'sig'):
        subterms(t[1], acc)
        subterms(t[2], acc)
    return acc


def universe(terms):
    """Closed set of terms to reason within: subterms of the given terms and their
    inverse keys. Derivability is decided within this finite set."""
    u = set()
    for t in terms:
        u |= subterms(t)
    # add inverse keys of any key that appears, so decryption targets are representable
    for t in list(u):
        u.add(inverse(t))
    return u


# ---- derivability -----------------------------------------------------------

def closure(known, univ):
    """Deductive closure of `known` within universe `univ`.

    Rules (applied to a fixpoint, only producing terms in univ):
      pair(a,b) known           => a, b        (projection)
      a, b known                => pair(a,b)    (pairing)
      enc(k,m), inverse(k) known=> m           (decryption)
      k, m known                => enc(k,m)     (encryption)
      sig(k,m) known            => m           (signatures expose the message)
      k, m known                => sig(k,m)     (signing)
    """
    K = set(known) & univ if False else set(known)
    changed = True
    while changed:
        changed = False
        # decomposition
        for t in list(K):
            if t[0] == 'pair':
                for part in (t[1], t[2]):
                    if part not in K:
                        K.add(part); changed = True
            elif t[0] == 'sig':
                if t[2] not in K:
                    K.add(t[2]); changed = True
            elif t[0] == 'enc':
                if inverse(t[1]) in K and t[2] not in K:
                    K.add(t[2]); changed = True
        # composition, restricted to univ so it terminates
        for a in list(K):
            # pairs
            for b in list(K):
                p = ('pair', a, b)
                if p in univ and p not in K:
                    K.add(p); changed = True
            # enc/sig with a as key
            for m in list(K):
                e = ('enc', a, m)
                if e in univ and e not in K:
                    K.add(e); changed = True
                s = ('sig', a, m)
                if s in univ and s not in K:
                    K.add(s); changed = True
    return K


def derivable(known, target):
    """Can the adversary derive `target` from `known`?"""
    univ = universe(list(known) + [target])
    return target in closure(known, univ)


# ---- self-test --------------------------------------------------------------

def _test():
    A = name('A'); B = name('B')
    kAB = name('k_AB'); skA = name('sk_A'); pkA = name('pk_A')
    m = name('m'); N = name('N')

    # symmetric decryption
    assert derivable({kAB, enc(kAB, m)}, m)
    assert not derivable({enc(kAB, m)}, m)
    # symmetric encryption
    assert derivable({kAB, m}, enc(kAB, m))
    assert not derivable({m}, enc(kAB, m))
    # public-key: encrypt with pk, need sk to open
    assert derivable({skA, enc(pkA, m)}, m)
    assert not derivable({pkA, enc(pkA, m)}, m)   # only public key: cannot open
    # signatures expose the message; forging needs the key
    assert derivable({sig(skA, m)}, m)
    assert derivable({skA, m}, sig(skA, m))
    assert not derivable({m, pkA}, sig(skA, m))   # cannot forge without sk_A
    # pairing / projection
    assert derivable({pair(A, B)}, A) and derivable({pair(A, B)}, B)
    assert derivable({A, B}, pair(A, B))
    # nested: {k_AB, enc(k_AB, pair(N, m))} => N and m
    assert derivable({kAB, enc(kAB, pair(N, m))}, N)
    assert derivable({kAB, enc(kAB, pair(N, m))}, m)
    print("dy.py: all tests passed")


if __name__ == '__main__':
    _test()
