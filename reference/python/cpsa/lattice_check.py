"""Cross-check: evaluate achievement at every point of the trust lattice 2^U with CPSA
and read off the minimal sufficient trusts directly (no loop, no stops)."""
import itertools, sys, time
import run_cegis, protocols

def lattice(oracle):
    U = sorted(oracle.U); t0 = time.time(); ok = {}
    for r in range(len(U) + 1):
        for T in itertools.combinations(U, r):
            ok[frozenset(T)] = oracle.achieves(set(T))
    suff = [T for T, v in ok.items() if v]
    mins = [sorted(T) for T in suff if not any(S < T for S in suff)]
    print(f"{oracle.name}: {len(ok)} lattice points, {sum(ok.values())} sufficient, "
          f"MinTrust = {mins or 'EMPTY = false'}  ({time.time()-t0:.2f}s)")

if __name__ == '__main__':
    for p in ('pkinit-flawed', 'pkinit-fix2'):
        lattice(run_cegis.pkinit_case(p))
    for name in protocols.CASES:
        lattice(protocols.CASES[name]())
