"""Run Algorithm 1 (cegis.py) with CPSA as the oracle and stops(x) read from CPSA's shapes.

    python3 cpsa/run_cegis.py            # PKINIT flawed and fixed
    python3 cpsa/run_cegis.py yahalom    # plus the extra protocol(s) in cpsa/protocols.py
"""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE)); sys.path.insert(0, HERE)

from cegis import cegis
import pkinit_mintrust as pk
from cpsa_oracle import CPSAOracle, CPSA

def pkinit_case(proto):
    U = {a: pk.FACT[a] for a in pk.U}
    def goal(facts):
        # reuse pkinit_mintrust.goal by temporarily matching its tau->facts interface
        tau = {a for a in pk.U if pk.FACT[a] in facts}
        return pk.goal(proto, tau)
    return CPSAOracle(proto, pk.PROTO[proto], U, goal)

def run(oracle):
    print(f"\n=== {oracle.name} ===   U = {sorted(oracle.U)}")
    calls = []
    def O(T):
        calls.append(frozenset(T)); return oracle(T)
    t0 = time.time()
    mt, H = cegis(O)
    wall = time.time() - t0
    fmt = lambda fam: [sorted(s) for s in fam]
    print(f"  conflicts H (= attacks(chi)) = {fmt(H)}")
    print(f"  MinTrust = {fmt(mt) if mt else 'EMPTY = false (no trust suffices)'}")
    s = oracle.stats
    print(f"  oracle invocations by the loop: {len(calls)}, distinct trusts queried: "
          f"{len(set(calls))} -> {[sorted(t) for t in dict.fromkeys(calls)]}")
    print(f"  CPSA runs: {s.goal_calls} goal runs ({s.goal_time:.2f}s) + "
          f"{s.check_calls} stops checks ({s.check_time:.2f}s); wall {wall:.2f}s")
    return mt, H

if __name__ == '__main__':
    print("CPSA binary:", CPSA)
    for p in ('pkinit-flawed', 'pkinit-fix2'):
        run(pkinit_case(p))
    if len(sys.argv) > 1:
        import protocols
        for name in sys.argv[1:]:
            run(protocols.CASES[name]())
