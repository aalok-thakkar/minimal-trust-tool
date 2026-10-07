"""CEGIS / hitting-set-tree loop for minimal trust.

Repairs the naive "attacks = shapes under empty trust". We discover conflicts lazily:
maintain known conflicts C; the candidate weakest trusts are blocker(C); query each
candidate with an achievement oracle; a failing candidate returns a fresh conflict
(the defence set of the attack the oracle found); add it, recompute, repeat.

oracle(tau) contract:
    return None            if tau achieves the goal (no attack survives)
    return a set s subset U if tau fails; s = stops(x) for the attack x the oracle found
                            (the assumptions that would have stopped it), a new conflict.

On termination every candidate passes, so blocker(C) are exactly the minimal trusts
(given a sound/complete oracle and finite U).

weakest() memoises the oracle on the frozenset trust and can minimalise witnesses
(shrink_witness); cegis() is the original interface.
"""

from hitting import blocker, minimalize

LAST_STATS = None          # stats of the most recent weakest()/cegis() run


def _order(T):
    """Candidate order: smaller trusts first, then lexicographic on repr. Fixed so that call
    counts do not depend on Python's per-process string hashing."""
    return (len(T), sorted(map(repr, T)))


def shrink_witness(ask, U, s):
    """Shrink a witness stopping set s to an inclusion-minimal stopping set E <= s.

    By Proposition 1, a set S contains a member of A(chi) iff the trust U - S fails. For each
    a in s, ask about U - (S - {a}); if it fails, its witness s' is a genuine stopping set with
    s' <= S - {a} (s' misses the trust), and S := s'; if it passes, S - {a} contains no member of
    A(chi), so a stays. At most |s| oracle calls. S is always stops(x) of a run the oracle
    produced, so with a bounded (incomplete) oracle the result is still a genuine stopping set,
    only possibly not minimal."""
    U, S = frozenset(U), frozenset(s)
    for a in sorted(s, key=repr):
        if a not in S:
            continue
        r = ask(U - (S - {a}))
        if r is not None:
            r = frozenset(r)
            if not r <= S - {a}:
                raise ValueError("oracle witness %r meets the trust it fails" % (set(r),))
            S = r
    return S


def weakest(oracle, U=None, shrink=False, max_iters=10000):
    """Algorithm 1 with a memo table. Returns (W, H, stats).

    oracle(T) -> None if T achieves the goal, else stops(x) for a witness run x.
    Each distinct trust is sent to the oracle once. stats:
      distinct  oracle calls actually made (Theorem 9 counts these)
      total     calls the unmemoised loop of the submitted Listing 1 would make
      shrink    distinct calls made by shrink_witness (included in distinct)
    shrink=True minimalises every witness before it enters H (needs U)."""
    global LAST_STATS
    memo, stats = {}, {'distinct': 0, 'total': 0, 'shrink': 0}

    def ask(T):
        T = frozenset(T)
        if T not in memo:
            stats['distinct'] += 1
            memo[T] = oracle(set(T))
        return memo[T]

    H = []
    for _ in range(max_iters):
        for T in sorted(blocker(H), key=_order):   # blocker([]) == [emptyset]
            stats['total'] += 1
            s = ask(T)
            if s is not None:                # T fails; s is a new conflict
                s = frozenset(s)
                if s & T or any(h <= s for h in H):
                    raise ValueError("unsound witness %r for candidate %r" % (set(s), set(T)))
                if shrink:
                    before = stats['distinct']
                    s = shrink_witness(ask, U, s)
                    stats['shrink'] += stats['distinct'] - before
                H = minimalize(H + [s])
                break
        else:                                # every candidate achieved the goal
            LAST_STATS = stats
            return blocker(H), H, stats
    raise RuntimeError("CEGIS did not converge; check oracle soundness/finiteness")


def cegis(oracle, max_iters=10000):
    """Return (MinTrust, conflicts). Backward-compatible wrapper; counts in LAST_STATS."""
    W, H, _ = weakest(oracle, max_iters=max_iters)
    return W, H


# ---- self-test: validate the pipeline against the paper's example -----------
# We encode the two cases of Section 2 as mock oracles and check MinTrust matches
# the answers stated in the paper, with no attack list given up front.

def _test():
    skA, skB = 'skA', 'skB'

    # Case 1 (signed challenge-response with names): forgery is stopped only by skA;
    # reflection is stopped by skA or skB but is subsumed once skA is kept. So the
    # sole minimal conflict the oracle ever needs to reveal is {skA}, and MinTrust={{skA}}.
    def oracle_with_names(tau):
        if skA not in tau:
            return {skA}                     # forgery witness
        return None
    mt, C = cegis(oracle_with_names)
    assert set(map(frozenset, mt)) == {frozenset({skA})}, mt

    # Case 2 (accepts either party's signature): one attack, two defences {skA,skB};
    # MinTrust = {{skA},{skB}}, the non-unique case, and the weakest trust is skA OR skB.
    def oracle_either(tau):
        if skA not in tau and skB not in tau:
            return {skA, skB}                # impersonation witness, either key stops it
        return None
    mt2, C2 = cegis(oracle_either)
    assert set(map(frozenset, mt2)) == {frozenset({skA}), frozenset({skB})}, mt2

    # A three-conflict case to exercise lazy discovery + subsumption.
    U_conf = [{'a'}, {'b', 'c'}]
    def oracle3(tau):
        for e in U_conf:
            if not (set(e) & tau):
                return set(e)
        return None
    mt3, _ = cegis(oracle3)
    assert set(map(frozenset, mt3)) == {frozenset({'a', 'b'}), frozenset({'a', 'c'})}, mt3

    # memo: a candidate that passed is not re-queried after a sibling fails
    _, _, st = weakest(oracle3)
    assert st['distinct'] <= st['total'], st

    # non-minimal witnesses: the oracle returns stops sets padded with extra atoms.
    # Without shrink the answer is still right (Theorem 8); with shrink every member of H
    # is minimal, so H equals A(chi) by involution.
    U = {'a', 'b', 'c', 'd'}
    A_true = [{'a'}, {'b', 'c'}]
    def padded(tau):
        for e in A_true:
            if not (set(e) & tau):
                return (set(e) | {'d'}) - tau     # genuine stopping set, not minimal
        return None
    W0, H0, st0 = weakest(padded)
    W1, H1, st1 = weakest(padded, U=U, shrink=True)
    want = {frozenset({'a', 'b'}), frozenset({'a', 'c'})}
    assert set(W0) == want and set(W1) == want, (W0, W1)
    assert set(H1) == {frozenset(e) for e in A_true}, H1
    print("cegis.py: padded witnesses: plain distinct=%d (H=%s); shrink distinct=%d of which shrink=%d"
          % (st0['distinct'], sorted(map(sorted, H0)), st1['distinct'], st1['shrink']))

    print("cegis.py: all tests passed (recovers the paper's Section 2 answers)")


if __name__ == '__main__':
    _test()
