"""Minimal trust for Kerberos PKINIT, driven by CPSA as the achievement oracle.

The goal (Cervesato et al.): a client strand that completes must be matched by a genuine AS
strand agreeing on (as, k, c) -- the client authenticates the AS. The tunable trust lives in the
goal's hypothesis as `non` facts over the private keys. We vary that trust and let cpsa4 decide
achievement (its `(satisfies yes)` / `(satisfies (no ...))` annotation), then read off the minimal
sufficient trust.

Universe U = { non(privk as), non(privk c) }.  (Freshness of n1,n2,k,ak is intrinsic to the roles.)
"""

import os, shutil, subprocess, itertools, tempfile

# CPSA 4 binary: $CPSA4 if set, else `cpsa4` on PATH, else ~/.local/bin/cpsa4 (see cpsa/README.md).
CPSA = (os.environ.get("CPSA4") or shutil.which("cpsa4")
        or os.path.expanduser("~/.local/bin/cpsa4"))

PROTO = {
"pkinit-flawed": """
(defprotocol pkinit-flawed basic
  (defrole client
    (vars (c t as name) (n2 n1 text) (tc tk tgt data) (k ak skey))
    (trace (send (cat (enc tc n2 (privk c)) c t n1))
      (recv (cat (enc (enc k n2 (privk as)) (pubk c)) c tgt (enc ak n1 tk t k))))
    (uniq-orig n1 n2))
  (defrole auth
    (vars (c t as name) (n2 n1 text) (tc tk tgt data) (k ak skey))
    (trace (recv (cat (enc tc n2 (privk c)) c t n1))
      (send (cat (enc (enc k n2 (privk as)) (pubk c)) c tgt (enc ak n1 tk t k))))
    (uniq-orig k ak)))
""",
"pkinit-fix2": """
(defprotocol pkinit-fix2 basic
  (defrole client
    (vars (c t as name) (n2 n1 text) (tc tk tgt data) (k ak skey))
    (trace (send (cat (enc tc n2 (privk c)) c t n1))
      (recv (cat (enc (enc k (hash (cat (enc tc n2 (privk c)) c t n1)) (privk as)) (pubk c))
                 c tgt (enc ak n1 tk t k))))
    (uniq-orig n1 n2))
  (defrole auth
    (vars (c t as name) (n2 n1 text) (tc tk tgt data) (k ak skey))
    (trace (recv (cat (enc tc n2 (privk c)) c t n1))
      (send (cat (enc (enc k (hash (cat (enc tc n2 (privk c)) c t n1)) (privk as)) (pubk c))
                 c tgt (enc ak n1 tk t k))))
    (uniq-orig k ak)))
""",
}

U = ['non_as', 'non_c']
FACT = {'non_as': '(non (privk as))', 'non_c': '(non (privk c))'}

def goal(proto, tau):
    facts = "\n                ".join(FACT[a] for a in U if a in tau)
    return f"""
(defgoal {proto}
  (forall ((c as name) (k skey) (z strd))
    (implies
      (and (p "client" z 2)
           (p "client" "c" z c)
           (p "client" "as" z as)
           (p "client" "k" z k)
                {facts})
      (exists ((z-0 strd))
        (and (p "auth" z-0 1) (p "auth" "as" z-0 as)
             (p "auth" "k" z-0 k) (p "auth" "c" z-0 c))))))
"""

def achieves(proto, tau):
    src = '(herald "pkinit mintrust")\n' + PROTO[proto] + goal(proto, tau)
    with tempfile.NamedTemporaryFile('w', suffix='.scm', delete=False) as f:
        f.write(src); path = f.name
    out = subprocess.run([CPSA, path], capture_output=True, text=True, timeout=120).stdout
    os.unlink(path)
    return ('(satisfies yes)' in out) and ('(satisfies (no' not in out)

def min_trust(proto):
    achieved = []
    for r in range(len(U) + 1):
        for tau in itertools.combinations(U, r):
            achieved.append((frozenset(tau), achieves(proto, set(tau))))
    suff = [t for t, ok in achieved if ok]
    minimal = [t for t in suff if not any(s < t for s in suff)]
    return achieved, minimal

if __name__ == '__main__':
    for proto in ('pkinit-flawed', 'pkinit-fix2'):
        print(f"\n=== {proto} ===")
        achieved, minimal = min_trust(proto)
        for tau, ok in achieved:
            print(f"  trust {sorted(tau) or '{}'}: {'ACHIEVES' if ok else 'attacked'}")
        print(f"  MinTrust = {[sorted(t) for t in minimal] if minimal else 'EMPTY (no trust suffices)'}")
