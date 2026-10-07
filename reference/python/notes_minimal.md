# Non-minimal witnesses: what the code does and how Theorem 9's bound changes

## The issue

Theorem 9 bounds the distinct oracle calls of Algorithm 1 by N = |A(chi)| + |W(chi)|
under the hypothesis that every witness the oracle returns has an inclusion-minimal
stopping set. CPSA does not promise this, and neither does a plain depth-first analyser:
in our bounded model of the signed challenge-response, the first attack the DFS finds
under the empty trust is a forgery of A's signature run alongside an unrelated session in
which A, as challenger, accepts a signature of B's that the adversary also forged. That run
is removed by Non(sk_A) and also by Non(sk_B), so its stopping set is
{Non(sk_A), Non(sk_B)}, which strictly contains the minimal attack {Non(sk_A)}.

## What the loop does without minimal witnesses (no code change needed)

Correctness (Theorem 8) does not use minimality. The call count does. Each failure adds a
stopping set s with s disjoint from the failing candidate T; since T meets every member of
the current H, s contains no member of H. A set added earlier and later removed by
minimalisation was removed because a subset of it entered H, so s cannot be one of those
either. Hence every failure adds a stopping set never added before, and

    distinct calls <= |W(chi)| + |S_O(chi)|,

where S_O(chi) is the family of stopping sets the oracle can return (at most 2^|U|). At
termination H = A(chi) all the same, by the involution: blocker(H) = W(chi), so
H = blocker(W(chi)) = A(chi).

## Optional minimalisation step (cegis.shrink_witness, `weakest(..., U=U, shrink=True)`)

By Proposition 1, a set S contains a member of A(chi) if and only if the trust U \ S fails.
Given a failing candidate and its witness stopping set s, put S := s and, for each a in s
still in S, query the trust U \ (S \ {a}):

* if it fails with witness s', then s' is disjoint from that trust, so s' is a subset of
  S \ {a}; set S := s' (this may drop several elements at once);
* if it passes, S \ {a} contains no member of A(chi), so a stays.

Each element of s is tested at most once, so the step costs at most |s| <= |U| extra
oracle calls, and the result is a member of A(chi). With every witness shrunk, each
failure adds a member of A(chi), and

    distinct calls <= |W(chi)| + sum over failures of (1 + |s_i|)
                   <= |W(chi)| + |A(chi)| * (1 + |U|),

where s_i is the witness stopping set of the i-th failure. The shrink queries are trusts of
the form U \ S'; the memo table means a query that coincides with a later candidate costs
nothing.

Soundness with a bounded or otherwise incomplete oracle: S is always the stopping set of
a run the oracle actually produced (it starts as s and is only ever replaced by another
witness), so the set added to H is always a genuine stopping set. Incompleteness can only
cause a wrong "pass" in the shrink step, which keeps an element and leaves S non-minimal;
it cannot make S wrong.

## Measured effect (reproduce.py --ablation)

| row | witnesses | distinct calls | of which shrink |
|---|---|---|---|
| signed CR | DFS run pruned to a minimal run (default) | 3 | 0 |
| signed CR | DFS run as found | 5 | 0 |
| signed CR | DFS run as found, shrink on | 6 | 4 |
| two-key | pruned (default) | 4 | 0 |
| two-key | as found | 4 | 0 |
| two-key | as found, shrink on | 5 | 3 |

On these small rows shrinking costs more calls than it saves: each shrink query on
U \ (S \ {a}) is a near-complete trust, and with |U| = 3 the loop recovers from a padded
witness in one or two extra candidates anyway. Shrinking pays when |U| is large relative to
the number of padded witnesses, and when the witness is far from minimal.

The default oracle in cr.py takes a different route: it prunes the witness run itself
(drops strand suffixes not needed for the attack, accepting a removal only if the run stays
executable, stays an attack, and its stopping set does not grow). That is run minimality,
which in general does not imply stopping-set minimality (the paper says so in the proof
sketch of Theorem 9); on the four analyser rows it gives minimal stopping sets, which is
an observation about these rows, not a property guaranteed by construction.

## Suggested paper text (draft)

"Theorem 9's call bound assumes minimal witnesses. Without that assumption each failure
still adds a stopping set not added before, so the loop makes at most
|W(chi)| + |S_O(chi)| distinct calls, with S_O(chi) the stopping sets the oracle can
return. A witness can be minimalised at the cost of at most |stops(x)| further calls: by
Proposition 1, S contains a minimal attack iff U \ S fails, so deleting one element at a
time and replacing S by the witness of each failing query yields a member of A(chi), and
the bound becomes |W(chi)| + |A(chi)|(1 + |U|)."
