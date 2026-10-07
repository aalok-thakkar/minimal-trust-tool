"""Clutters, minimal hitting sets, and the blocker.

MinTrust(chi) = blocker(conflict clutter). We compute minimal transversals by Berge's
incremental algorithm, and expose minimalize() (subsumption removal) so the conflict family
is always a clutter. The blocker is an involution on clutters (Edmonds-Fulkerson 1970),
which the tests check.
"""

def minimalize(sets):
    """Reduce a family to a clutter: keep only inclusion-minimal members."""
    out = []
    for s in sorted(set(map(frozenset, sets)), key=len):   # smaller sets first
        if not any(t <= s for t in out):   # no kept set is contained in s
            out.append(s)
    return out


def min_transversals(H):
    """All inclusion-minimal hitting sets of the family H (Berge incremental).

    A transversal meets every edge. min_transversals([]) = [emptyset]: the empty set hits
    every one of no edges. Returns a list of frozensets, itself a clutter."""
    cur = [frozenset()]
    for edge in H:
        e = frozenset(edge)
        nxt = []
        for part in cur:
            if part & e:                    # already hits this edge
                nxt.append(part)
            else:
                for a in e:                 # extend by one element of the edge
                    nxt.append(part | {a})
        cur = minimalize(nxt)
    return minimalize(cur)


def blocker(H):
    """Blocker of a clutter: the clutter of its minimal transversals."""
    return min_transversals(minimalize(H))


# ---- self-test --------------------------------------------------------------

def _eqfam(a, b):
    return set(map(frozenset, a)) == set(map(frozenset, b))


def _test():
    a, b, c = 'a', 'b', 'c'
    # singletons
    assert _eqfam(blocker([{a}]), [{a}])
    # one two-element conflict -> two singleton trusts (the RGL either-key case)
    assert _eqfam(blocker([{a, b}]), [{a}, {b}])
    # subsumption: {a} and {a,b} -> clutter {a} -> unique {a}
    assert _eqfam(minimalize([{a}, {a, b}]), [{a}])
    assert _eqfam(blocker([{a}, {a, b}]), [{a}])
    # crossing conflicts
    assert _eqfam(blocker([{a, b}, {b, c}]), [{b}, {a, c}])
    # empty family -> empty transversal
    assert _eqfam(min_transversals([]), [set()])
    # involution b(b(H)) = minimalize(H) on a few clutters
    for H in ([{a, b}], [{a, b}, {b, c}], [{a}, {b, c}], [{a, b}, {a, c}, {b, c}]):
        assert _eqfam(blocker(blocker(H)), minimalize(H)), H
    print("hitting.py: all tests passed")


if __name__ == '__main__':
    _test()
