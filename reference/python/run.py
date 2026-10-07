"""End-to-end: validate the analyzer against known facts, then recover minimal trust
via the CEGIS loop, for NSPK and its fix NSL. Run: python3 run.py"""

from analyzer import achieve
from cegis import cegis

skA, skB = ('Non', 'sk_A'), ('Non', 'sk_B')

def oracle_for(nsl):
    def oracle(tau):
        r = achieve(nsl, set(tau))
        return None if r is None else r[1]   # conflict = the attack's defence set
    return oracle

# validation against known facts (regression)
r = achieve(False, {skA, skB})
assert r is not None and set(r[1]) == set(), ("NSPK should be attacked, empty defence", r)
assert achieve(True, {skA}) is None,          "NSL should achieve under Non(sk_A)"
assert achieve(True, {skB}) is not None,       "NSL should still fail under only Non(sk_B)"
assert set(achieve(True, set())[1]) == {skA},  "NSL no-trust attack defence should be {Non(sk_A)}"

# recovered minimal trust
mt_nspk, _ = cegis(oracle_for(False))
mt_nsl,  _ = cegis(oracle_for(True))
assert [set(t) for t in mt_nspk] == [],        "NSPK: no sufficient trust expected"
assert [set(t) for t in mt_nsl] == [{skA}],    "NSL: MinTrust should be {{Non(sk_A)}}"

print("all validations passed")
print("NSPK  MinTrust =", [set(t) for t in mt_nspk], " (no trust suffices; Lowe's attack)")
print("NSL   MinTrust =", [set(t) for t in mt_nsl], " (only the peer's key, not the responder's own)")
