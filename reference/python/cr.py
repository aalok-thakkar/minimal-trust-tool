"""Bounded Dolev-Yao achievement oracles for the challenge-response rows of Table 2.

Protocols (Section 2 of the paper), B the challenger and A the prover:

    signed   B -> A : N        A -> B : sig_{sk_A}(N, A, B)
    twokey   B -> A : N        A -> B : {| {| N, A, B |}_{k1} |}_{k2}
    signed_nonames (probe)     A -> B : sig_{sk_A}(N)
    shared_nonames (probe)     A -> B : {| N |}_{k_AB}     (classic reflection target)

The two probes are not Table 2 rows; they answer the question whether the "reflection"
row of Table 1 is an attack in this model.

Model (same engine style as analyzer.py). The intruder is the network: every honest send is
added to its knowledge K, every honest receive is any instance of the expected template that
is derivable from K (dy.derivable). Bounded strand pool (both parties run both roles, and A
will also answer the intruder):

    0  Chal(B, A)  test strand: send N_t ; recv resp(A, B, N_t)
    1  Prov(A, B)  recv n ; send resp(A, B, n)
    2  Prov(B, A)  recv n ; send resp(B, A, n)          (role swap: B as prover)
    3  Chal(A, B)  send N_a ; recv resp(B, A, N_a)        (role swap: A as challenger)
    4  Prov(A, I)  recv n ; send resp(A, I, n)            (A answers the intruder)

plus one earlier, completed honest session Prov(A, B) on nonce N_old, whose transcript
(N_old and resp(A, B, N_old)) is in the intruder's initial knowledge.

Trust atoms. Non(k): k is not in the intruder's initial knowledge. Unq(N): the test nonce
originates only at the test strand. Without Unq(N) the test strand's nonce N_t is either a
fresh atom N or the stale N_old of the earlier session; with Unq(N) it is N.

Goal (recent agreement for B): when Chal(B, A) completes with nonce N_t, the honest
Prov(A, B) strand has completed on N_t and sent its response after the test strand sent N_t.
An attack is a reachable state violating this.

stops(x) for a found run x (Definition 3):
    Non(k)  iff k is not assumed, and replaying x with k removed from the initial knowledge
            leaves some receive underivable;
    Unq(N)  iff N_t = N_old in x (the test nonce originated twice).
"""

from time import perf_counter
from dy import name, pair, enc, sig, derivable
from analyzer import inst, free_vars, _assignments, _flatten_heads

A, B, I = name('A'), name('B'), name('I')
N, N_OLD, N_A = name('N'), name('N_old'), name('N_a')
UNQ = ('Unq', 'N')

PROTOCOLS = {
    #  name           : (keys whose Non is in U, resp(prover, peer, n))
    'signed':         (('sk_A', 'sk_B'),
                       lambda p, q, n: sig(name('sk_' + p[1]), pair(n, pair(p, q)))),
    'twokey':         (('k1', 'k2'),
                       lambda p, q, n: enc(name('k2'), enc(name('k1'), pair(n, pair(p, q))))),
    'signed_nonames': (('sk_A', 'sk_B'),
                       lambda p, q, n: sig(name('sk_' + p[1]), n)),
    'shared_nonames': (('k_AB',),
                       lambda p, q, n: enc(name('k_AB'), n)),
}


def universe_U(proto):
    """The generators U of the row: Non of each key, and Unq(N)."""
    keys, _ = PROTOCOLS[proto]
    return [('Non', k) for k in keys] + [UNQ]


def _v(sid):
    return ('var', sid, 'n')


def scenario(proto, n_test):
    _, resp = PROTOCOLS[proto]
    return [
        ('Chal', B, A, [('send', n_test), ('recv', resp(A, B, n_test))]),
        ('Prov', A, B, [('recv', _v(1)), ('send', resp(A, B, _v(1)))]),
        ('Prov', B, A, [('recv', _v(2)), ('send', resp(B, A, _v(2)))]),
        ('Chal', A, B, [('send', N_A), ('recv', resp(B, A, N_A))]),
        ('Prov', A, I, [('recv', _v(4)), ('send', resp(A, I, _v(4)))]),
    ]


POOL = [A, B, I, N, N_OLD, N_A]          # values a received variable may take (atoms only)


def initial_knowledge(proto, tau):
    keys, resp = PROTOCOLS[proto]
    K = {A, B, I, name('pk_A'), name('pk_B'), name('pk_I'), name('sk_I')}
    K |= {N_OLD, resp(A, B, N_OLD)}                  # transcript of the earlier session
    for k in keys:
        if ('Non', k) not in tau:
            K.add(name(k))                            # compromised
    return frozenset(K)


def _search(proto, tau, n_test, enumerate_all=False):
    """DFS over interleavings of the pool. Yields (trace, stops) for attack states.

    A state is (positions, K, binding, broken, good):
      broken  the compromised keys k such that some receive so far is underivable from K - {k}
              (replaying the run without k breaks it, so Non(k) is in stops);
      good    Prov(A,B) has sent its response on N_t after the test strand sent N_t.
    Two interleavings reaching the same state have the same stops and the same future, so
    states are deduplicated; enumeration counts distinct attack states, not traces."""
    strands = scenario(proto, n_test)
    K0 = initial_knowledge(proto, tau)
    keys = [name(k) for k in PROTOCOLS[proto][0] if name(k) in K0]
    seen = set()
    stack = [((tuple(0 for _ in strands), K0, frozenset(), frozenset(), False), [])]
    while stack:
        state, trace = stack.pop()
        if state in seen:
            continue
        seen.add(state)
        pos, K, binding, broken, good = state
        if pos[0] == 2 and not good:              # test completed without recent agreement
            s = {('Non', k[1]) for k in broken}
            if n_test == N_OLD:
                s.add(UNQ)
            yield trace, frozenset(s)
            if not enumerate_all:
                return
            continue                              # do not extend an attack state
        bd = dict(binding)
        for sid, (_, _, _, steps) in enumerate(strands):
            if pos[sid] >= len(steps):
                continue
            kind, term = steps[pos[sid]]
            npos = tuple(p + 1 if i == sid else p for i, p in enumerate(pos))
            if kind == 'send':
                msg = inst(term, bd)
                ngood = good or (sid == 1 and pos[0] >= 1 and bd.get(_v(1)) == n_test)
                stack.append(((npos, K | {msg}, binding, broken, ngood),
                              trace + [('send', sid, msg)]))
            else:
                fvs = set(); free_vars(term, bd, fvs)
                for assign in _assignments(sorted(fvs), POOL):
                    nb = dict(bd); nb.update(assign)
                    msg = inst(term, nb)
                    if 'var' in _flatten_heads(msg):
                        continue
                    if derivable(set(K), msg):
                        nbroken = broken | {k for k in keys
                                            if k not in broken and not derivable(set(K) - {k}, msg)}
                        stack.append(((npos, K, frozenset(nb.items()), frozenset(nbroken), good),
                                      trace + [('recv', sid, msg)]))


def _choices(tau):
    # search order: the fresh test nonce first, then (if Unq(N) is not assumed) the stale one
    return [N] if UNQ in tau else [N, N_OLD]


# ---- witness runs: replay, stopping sets, and pruning to a minimal run --------

def _replays(K0, trace):
    """Is trace an execution from initial knowledge K0 (every receive derivable)?"""
    K = set(K0)
    for kind, _, msg in trace:
        if kind == 'send':
            K.add(msg)
        elif not derivable(K, msg):
            return False
    return True


def _is_attack(trace, n_test):
    """Test strand completed, and Prov(A,B) did not send its response on N_t after the test
    strand sent N_t."""
    ev = [i for i, e in enumerate(trace) if e[1] == 0]
    if len(ev) < 2:
        return False
    t_send = ev[0]
    got = None
    for i, (kind, sid, msg) in enumerate(trace):
        if sid == 1 and kind == 'recv':
            got = msg
        if sid == 1 and kind == 'send' and got == n_test and i > t_send:
            return False
    return True


def trace_stops(proto, tau, trace, n_test):
    """Definition 3 on a run: Non(k) if replaying without k breaks it; Unq(N) if N_t = N_old."""
    K0 = initial_knowledge(proto, tau)
    s = {('Non', k) for k in PROTOCOLS[proto][0]
         if name(k) in K0 and not _replays(K0 - {name(k)}, trace)}
    if n_test == N_OLD:
        s.add(UNQ)
    return frozenset(s)


def prune(proto, tau, trace, n_test):
    """Shrink a witness run: repeatedly drop the last event of some non-test strand while what
    remains is still an execution, still an attack, and its stopping set does not grow.
    (Dropping an honest send can force the intruder onto a key, so the last condition is
    needed.) The result has no removable strand suffix of that kind, and
    stops(result) <= stops(trace)."""
    K0 = initial_knowledge(proto, tau)
    cur = trace_stops(proto, tau, trace, n_test)
    changed = True
    while changed:
        changed = False
        for sid in sorted({e[1] for e in trace if e[1] != 0}):
            last = max(i for i, e in enumerate(trace) if e[1] == sid)
            cand = trace[:last] + trace[last + 1:]
            if _replays(K0, cand) and _is_attack(cand, n_test):
                s = trace_stops(proto, tau, cand, n_test)
                if s <= cur:
                    trace, cur, changed = cand, s, True
    return trace


def achieve(proto, tau, minimal_run=True):
    """None if recent agreement holds under tau in the bounded model; else (trace, stops).
    minimal_run=True prunes the first attack the DFS finds to a minimal run before computing
    stops; minimal_run=False returns the DFS run as found."""
    for n_test in _choices(tau):
        for trace, s in _search(proto, tau, n_test):
            if minimal_run:
                trace = prune(proto, tau, trace, n_test)
                s = trace_stops(proto, tau, trace, n_test)
            return trace, s
    return None


def oracle_for(proto, minimal_run=True):
    def oracle(tau):
        r = achieve(proto, set(tau), minimal_run)
        return None if r is None else r[1]
    return oracle


def enumerate_attacks(proto, tau=frozenset(), minimal_run=False):
    """All attack states under tau, grouped by stopping set (of the run as found, or of its
    pruned minimal run). Returns {stops: (count, shortest trace, n_test)}."""
    out = {}
    for n_test in _choices(tau):
        for trace, s in _search(proto, tau, n_test, enumerate_all=True):
            if minimal_run:
                trace = prune(proto, tau, trace, n_test)
                s = trace_stops(proto, tau, trace, n_test)
            c, best, nt = out.get(s, (0, None, None))
            if best is None or len(trace) < len(best):
                best, nt = trace, n_test
            out[s] = (c + 1, best, nt)
    return out


# ---- pretty printing --------------------------------------------------------

ROLE = {0: 'Chal(B,A)*', 1: 'Prov(A,B)', 2: 'Prov(B,A)', 3: 'Chal(A,B)', 4: 'Prov(A,I)'}


def show(t):
    if t[0] == 'name':
        return t[1]
    if t[0] == 'pair':
        return '%s,%s' % (show(t[1]), show(t[2]))
    if t[0] == 'sig':
        return 'sig_%s(%s)' % (show(t[1]), show(t[2]))
    if t[0] == 'enc':
        return '{|%s|}_%s' % (show(t[2]), show(t[1]))
    return str(t)


def show_trace(trace):
    return '; '.join('%s %s %s' % (ROLE[sid], k, show(m)) for k, sid, m in trace)


def show_set(s):
    return '{' + ', '.join('%s(%s)' % a for a in sorted(s)) + '}'


def report_enumeration(proto, minimal_run=False):
    t0 = perf_counter()
    groups = enumerate_attacks(proto, minimal_run=minimal_run)
    print('%s: attack states under the empty trust, grouped by stopping set of %s (%.2fs)'
          % (proto, 'the pruned minimal run' if minimal_run else 'the run as found',
             perf_counter() - t0))
    for s, (c, tr, nt) in sorted(groups.items(), key=lambda kv: (len(kv[0]), show_set(kv[0]))):
        print('  stops=%-28s runs=%-5d N_t=%-5s e.g. %s' % (show_set(s), c, show(nt), show_trace(tr)))


if __name__ == '__main__':
    import sys
    protos = sys.argv[1:] or ['signed', 'twokey', 'signed_nonames', 'shared_nonames']
    for p in protos:
        report_enumeration(p)
        report_enumeration(p, minimal_run=True)
