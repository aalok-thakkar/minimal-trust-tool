"""Differential-test driver: random clutters through the Python reference.

Writes, for each case, the input family and the Python results of hitting.blocker and
cegis.weakest (minimal witnesses; and padded witnesses with shrink) to stdout, in the
line format read by test/diff_python.ml. Usage:
    python3 diff_driver.py ARTIFACT_DIR SEED COUNT_SMALL COUNT_LARGE
Small cases (n <= 10) run blocker and both loop modes; large cases (n <= 18) run only
the blocker.
"""
import random
import sys

sys.path.insert(0, sys.argv[1])
from hitting import blocker, minimalize  # noqa: E402
from cegis import weakest  # noqa: E402


def canon(F):
    return sorted((sorted(s) for s in set(map(frozenset, F))), key=lambda s: (len(s), s))


def emit_fam(tag, F):
    F = canon(F)
    print("FAM %s %d" % (tag, len(F)))
    for s in F:
        print(" ".join(["S"] + s))


def gen(rng, nmax, emax):
    n = rng.randint(1, nmax)
    U = ["x%02d" % j for j in range(n)]
    m = rng.randint(0, 2 * n)
    H = []
    for _ in range(m):
        if rng.randrange(40) == 0:
            H.append(set())
        else:
            H.append(set(rng.sample(U, rng.randint(1, min(n, emax)))))
    return U, H


def main():
    seed, small, large = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    rng = random.Random(seed)
    for i in range(small + large):
        loop = i < small
        U, H = gen(rng, 10 if loop else 18, 4)
        print("CASE %d %d" % (i, 1 if loop else 0))
        print(" ".join(["U"] + U))
        print("FAM H %d" % len(H))          # raw input, duplicates and order kept
        for s in H:
            print(" ".join(["S"] + sorted(s)))
        emit_fam("B", blocker(H))
        if loop:
            A = canon(minimalize(H))

            def minimal(tau):
                for e in A:
                    if not set(e) & tau:
                        return set(e)
                return None

            def padded(tau):
                for e in A:
                    if not set(e) & tau:
                        rest = sorted(set(U) - tau - set(e))
                        return set(e) | ({rest[0]} if rest else set())
                return None

            W, HH, st = weakest(minimal)
            emit_fam("W", W)
            emit_fam("HH", HH)
            print("STAT min %d %d %d" % (st["distinct"], st["total"], st["shrink"]))
            W2, H2, st2 = weakest(padded, U=set(U), shrink=True)
            emit_fam("W2", W2)
            emit_fam("H2", H2)
            print("STAT shrink %d %d %d" % (st2["distinct"], st2["total"], st2["shrink"]))
        print("END")


if __name__ == "__main__":
    main()
