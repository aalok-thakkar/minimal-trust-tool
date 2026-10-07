# Computing stops(x) from a verifier's counterexample

Covers how stops(x) is obtained from an arbitrary backend, why CPSA's witnesses need not
have minimal stopping sets (the cost theorem's bound assumes they do), and a run of the loop
on PKINIT.
Implementation: `cpsa_oracle.py`. Runs: `run_cegis.out`.

## What a backend must offer

Two operations, both of which CPSA, ProVerif-style trace verifiers and bounded model checkers
already have in some form:

1. **verify(T)**: decide whether the goal holds under trust T; on failure, return one or more
   counterexamples x (runs, or symbolic descriptions of runs).
2. **replay(x, M)**: given a counterexample x found under T and a set M of extra assumptions,
   decide whether x is still a run of the model once M is assumed as well.

Nothing else is needed: no access to the adversary's derivation, no knowledge of how the
backend represents assumptions.

## Recipe

Given a failing trust T and a counterexample x:

```
M := {}
for a in U \ T (any fixed order):
    if replay(x, M ∪ {a}) says x survives:
        M := M ∪ {a}
stops(x) := (U \ T) \ M
```

Cost: |U \ T| replay calls per counterexample. When verify returns several counterexamples,
compute stops for each and pass the ⊆-minimal one to Algorithm 1 (or add all of them to H;
each is a genuine conflict).

**Soundness, unconditionally.** x is a run under T ∪ M by construction. Any trust τ with
τ ∩ stops(x) = ∅ satisfies τ ⊆ T ∪ M, so by monotonicity (Lemma `lem:monotone`: assuming less admits more
runs) x is a run under τ and τ fails. Hence every sufficient trust meets stops(x): it is a
conflict in the sense Algorithm 1 needs, and the correctness argument (Theorem `thm:correctness`) goes through.

**Agreement with Definition `def:attacks`.** If x is a single run, then x survives M iff it survives
each a ∈ M separately (it violates a set of assumptions iff it violates one of them), and
the greedy loop returns exactly {a ∈ U \ T : assuming a rules out x}, independent of order.
If the backend's counterexample is symbolic and stands for a family of runs (a CPSA shape is
a skeleton, realised by many bundles), survival of the family need not decompose atom by
atom: the family may survive {a} and {b} through different members but not {a, b}. The
greedy version is still sound in that case; it implicitly selects a member of the family and
returns that member's stopping set. Testing atoms one at a time and taking
{a : x does not survive {a}} would not be sound there, which is why the recipe accumulates M.
In all runs below the greedy and per-atom answers coincide.

**Minimality.** stops(x) is exact for the run x (no over- or under-approximation).
It is not guaranteed to be a ⊆-minimal member of attacks(χ): that depends on which
counterexample the backend returns. CPSA returns shapes, which are minimal in the
homomorphism order on skeletons; that order is unrelated to inclusion of stopping sets.
Theorem 9's bound of N distinct oracle calls therefore applies to CPSA only when its shapes
happen to have minimal stopping sets. Choosing the ⊆-minimal stopping set among all shapes
of one CPSA run narrows the gap but does not close it.

## CPSA instantiation

- verify(T): the trust T becomes facts in the hypothesis of a `defgoal`; cpsa4 is run once.
  Each shape annotated `(satisfies (no ...))` is a counterexample. The annotation also
  lists the bindings of the goal's universally quantified variables to the shape's terms,
  e.g. `(c c) (as as) (k k) (z 0)`.
- replay(x, M): instantiate each atom of M (a goal fact over goal variables, e.g.
  `(non (privk c))`, `(uniq n-b)`) with those bindings; append the terms to the shape's
  `non-orig` or `uniq-orig` list; print the shape back as a `defskeleton` (strands,
  `precedes`, origination assumptions); run cpsa4 on it. x survives iff CPSA reports the
  input skeleton (label 0) as `(realized)`. If CPSA rejects the skeleton as ill-formed
  (e.g. `uniq-orig` on a value that two regular strands originate), x does not survive.
- A run that does not end with `Nothing left to do`, or that reports
  `Step limit exceeded` or `Strand bound exceeded`, is treated as an error, not as an answer.

Reading origination off the shape directly (does a regular strand of x carry the key? does a
nonce originate twice?) decides some atoms without a CPSA call, but not whether the adversary
needs a key to realise a reception, since CPSA does not print adversary derivations. The
replay call decides that case, so the implementation uses replay for every atom.

## What came out (CPSA 4.4.9)

| protocol | U | distinct oracle calls (goal runs) | replay calls | N = \|attacks\| + \|weakest\| | answer |
|---|---|---|---|---|---|
| PKINIT flawed | non(sk C), non(sk S) | 2 | 3 | 1 + 0 = 1 | false |
| PKINIT fixed | non(sk C), non(sk S) | 2 | 2 | 1 + 1 = 2 | {non(sk S)} |
| Yahalom, resp. agrees with init. on (a,b,c,k) | non(ltk a c), non(ltk b c), uniq(n_a), uniq(n_b) | 3 | 10 | 2 + 1 = 3 | {non(ltk a c), non(ltk b c)} |

Flawed PKINIT exceeds the minimal-witness bound by one call, a concrete case where the
witnesses are not minimal. Under T = ∅, CPSA's only shape is the client strand alone (the adversary
forges the server's signature); its stopping set is {non(sk S)}, which is not minimal,
since attacks(χ) = {∅}. The loop then queries {non(sk S)}, gets the Cervesato
man-in-the-middle shape with stopping set ∅, and returns false. A backend with minimal
witnesses would have returned the man-in-the-middle run at T = ∅ and stopped after one call.

On Yahalom the second goal run returned two failing shapes: one (server strand present,
adversary learns k through ltk(a,c)) with stopping set {non(ltk a c)}, and one (the key from
a different responder session) with {non(ltk a c), uniq(n_b)}. The loop used the minimal one.
Freshness of either nonce is not needed for this goal, which asks for agreement, not recency.

All three answers match exhaustive evaluation of the trust lattice with CPSA
(`lattice_check.out`: 4, 4 and 16 points).
