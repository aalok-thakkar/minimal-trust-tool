"""Theorem thm:composition (composition) on two concrete pairs of protocols.

Self-contained: uses only dy.py (term algebra, derivability). The loop of Algorithm 1 and the
blocker are re-implemented here so this file does not depend on cegis.py / hitting.py, which
are being edited separately. Run: python3 composition.py

Protocols (A is the signer whose key sk_A is shared by both protocols in every pair).

  P1, signed challenge-response (Section 2):
      B -> A : N
      A -> B : sig(sk_A, <[cr,] N, A, B>)
    goal chi1 (recent agreement): when B's run completes, A ran a P1 responder strand
    with B on N, and A's signature was sent after B's challenge.

  P2, an attestation service with authenticated requests:
      C -> A : sig(sk_C, <M, B>)          (C asks A to attest M to B)
      A -> B : sig(sk_A, <[att,] M, A, B>)
    goal chi2 (non-injective agreement): when B accepts an attestation of M, A ran a P2
    attester strand for B on M.

  Pair 1: tags cr / att present, so the two signed formats cannot be confused.
  Pair 2: tags absent; both protocols sign <x, A, B> under sk_A (shared key infrastructure).

Generators U = {Non(sk_A), Non(sk_C), Unq(N)}, common to all runs.
  Non(k) assumed  <=> k is not in the adversary's initial knowledge.
  Unq(N) assumed  <=> N is not in the adversary's initial knowledge (otherwise N is a repeated
                      value the adversary can use before B sends it: pre-play / replay).

Bounded model: the adversary is the network; one strand per role (B_P1, A_P1, C_P2, A_P2,
B_P2); received variables range over {N, m_C, x}, where m_C is C's value and x is a value of
the adversary's own. stops(x) of a run = the atoms in U, not already assumed, whose removal of
the corresponding term from the initial knowledge makes some reception of that run
underivable (the per-atom replay check of analyzer._stops). The oracle explores every
reachable state and returns an attack with a subset-minimal stopping set (minimal witnesses,
Theorem thm:cost).
"""

from itertools import combinations
from dy import name, pair, sig, derivable

A, B, C = name('A'), name('B'), name('C')
skA, skC = name('sk_A'), name('sk_C')
N, mC, xI = name('N'), name('m_C'), name('x')
TAG_CR, TAG_ATT = name('cr'), name('att')

NON_SKA, NON_SKC, UNQ_N = 'Non(sk_A)', 'Non(sk_C)', 'Unq(N)'
U = [NON_SKA, NON_SKC, UNQ_N]
TERM_OF = {NON_SKA: skA, NON_SKC: skC, UNQ_N: N}
VALUES = [N, mC, xI]


def V(label):
    return ('var', label)


def body(tag, v, tagged):
    core = pair(v, pair(A, B))
    return pair(tag, core) if tagged else core


# ---- strands ---------------------------------------------------------------
# strand = (id, protocol, list of (kind, term)). Variables are global labels ('var', l).

def p1_strands(tagged):
    return [
        ('B_P1', 'P1', [('send', N), ('recv', sig(skA, body(TAG_CR, N, tagged)))]),
        ('A_P1', 'P1', [('recv', V('n')), ('send', sig(skA, body(TAG_CR, V('n'), tagged)))]),
    ]


def p2_strands(tagged):
    return [
        ('C_P2', 'P2', [('send', sig(skC, pair(mC, B)))]),
        ('A_P2', 'P2', [('recv', sig(skC, pair(V('m'), B))),
                        ('send', sig(skA, body(TAG_ATT, V('m'), tagged)))]),
        ('B_P2', 'P2', [('recv', sig(skA, body(TAG_ATT, V('M'), tagged)))]),
    ]


def inst(t, bd):
    if t[0] == 'var':
        return bd.get(t[1], t)
    if t[0] in ('pair', 'enc', 'sig'):
        return (t[0], inst(t[1], bd), inst(t[2], bd))
    return t


def fvars(t, bd, acc):
    if t[0] == 'var':
        if t[1] not in bd:
            acc.add(t[1])
    elif t[0] in ('pair', 'enc', 'sig'):
        fvars(t[1], bd, acc); fvars(t[2], bd, acc)


# ---- goals -----------------------------------------------------------------

def chi1_fails(st):
    """B_P1 completed, and no A_P1 strand agreed on N with its signature after B's challenge."""
    pos, bd, ev = st['pos'], st['bd'], st['events']
    if pos['B_P1'] < 2:
        return False
    for (sid, step, after_challenge) in ev:
        if sid == 'A_P1' and step == 1 and bd.get('n') == N and after_challenge:
            return False
    return True


def chi2_fails(st):
    """B_P2 completed on M, and no A_P2 strand sent an attestation of M."""
    pos, bd, ev = st['pos'], st['bd'], st['events']
    if pos['B_P2'] < 1:
        return False
    for (sid, step, _) in ev:
        if sid == 'A_P2' and step == 1 and bd.get('m') == bd.get('M'):
            return False
    return True


# ---- the bounded oracle ------------------------------------------------------

def K0_of(tau):
    K = {A, B, C, name('I'), xI, TAG_CR, TAG_ATT}
    for a in U:
        if a not in tau:
            K.add(TERM_OF[a])
    return frozenset(K)


def oracle(strands, goals, tau):
    """None if tau achieves every goal in `goals`; else (stops, trace, goal_name) for an
    attack whose stopping set is subset-minimal among all attacks reachable under tau."""
    K0 = K0_of(tau)
    free = [a for a in U if a not in tau]
    ids = [s[0] for s in strands]
    steps = {s[0]: s[2] for s in strands}
    start = (tuple(0 for _ in ids), frozenset(), frozenset(), frozenset(), frozenset())
    seen, stack, found = set(), [(start, ())], {}
    while stack:
        state, trace = stack.pop()
        if state in seen:
            continue
        seen.add(state)
        pos_t, sends, bd_items, events, used = state
        pos = dict(zip(ids, pos_t)); bd = dict(bd_items)
        st = {'pos': pos, 'bd': bd, 'events': events}
        for gname, gfail in goals:
            if gfail(st):
                key = frozenset(used)
                if key not in found:
                    found[key] = (trace, gname)
        K = set(K0) | set(sends)
        for i, sid in enumerate(ids):
            if pos[sid] >= len(steps[sid]):
                continue
            kind, term = steps[sid][pos[sid]]
            npos = tuple(p + 1 if j == i else p for j, p in enumerate(pos_t))
            if kind == 'send':
                msg = inst(term, bd)
                after = pos.get('B_P1', 0) >= 1
                nev = events | {(sid, pos[sid], after)}
                stack.append(((npos, sends | {msg}, bd_items, nev, used),
                              trace + (('send', sid, msg),)))
            else:
                fv = set(); fvars(term, bd, fv); fv = sorted(fv)
                for vals in _tuples(len(fv)):
                    nb = dict(bd); nb.update(zip(fv, vals))
                    msg = inst(term, nb)
                    if not derivable(K, msg):
                        continue
                    nused = set(used)
                    for a in free:
                        Ka = (set(K0) - {TERM_OF[a]}) | set(sends)
                        if not derivable(Ka, msg):
                            nused.add(a)
                    stack.append(((npos, sends, frozenset(nb.items()), events,
                                   frozenset(nused)),
                                  trace + (('recv', sid, msg),)))
    if not found:
        return None
    mins = [s for s in found if not any(t < s for t in found)]
    best = min(mins, key=lambda s: (len(s), sorted(s)))
    trace, gname = found[best]
    return set(best), trace, gname


def _tuples(k):
    if k == 0:
        yield (); return
    for v in VALUES:
        for rest in _tuples(k - 1):
            yield (v,) + rest


# ---- Algorithm 1 and the blocker --------------------------------------------

def minimalize(F):
    F = list({frozenset(s) for s in F})
    return [s for s in F if not any(t < s for t in F)]


def blocker(H):
    cur = [frozenset()]
    for e in minimalize(H):
        nxt = []
        for part in cur:
            nxt.extend([part] if part & e else [part | {a} for a in e])
        cur = minimalize(nxt)
    return minimalize(cur)


def algorithm1(orc, log):
    H, calls = [], 0
    while True:
        for T in sorted(blocker(H), key=lambda s: (len(s), sorted(s))):
            calls += 1
            r = orc(set(T))
            if r is not None:
                stops, trace, g = r
                log.append((set(T), stops, g, trace))
                H = minimalize(H + [stops])
                break
            log.append((set(T), None, None, None))
        else:
            return blocker(H), H, calls


def join(W1, W2):
    """Join in the completion (Corollary cor:conjunction): minimal pairwise unions."""
    return minimalize([a | b for a in W1 for b in W2])


# ---- reporting ---------------------------------------------------------------

def show(t):
    if t[0] == 'name':
        return t[1]
    if t[0] == 'pair':
        return '<' + ', '.join(show(x) for x in _flat(t)) + '>'
    if t[0] == 'sig':
        return 'sig(%s, %s)' % (show(t[1]), show(t[2]))
    if t[0] == 'var':
        return '?' + t[1]
    return str(t)


def _flat(t):
    return (_flat(t[1]) + _flat(t[2])) if t[0] == 'pair' else [t]


def fam(F):
    if F == []:
        return 'false (empty antichain)'
    return '{' + ', '.join('{' + ', '.join(sorted(s)) + '}' for s in
                           sorted(F, key=lambda s: (len(s), sorted(s)))) + '}'


def run(label, strands, goals, verbose=True):
    log = []
    W, H, calls = algorithm1(lambda T: oracle(strands, goals, T), log)
    print('  %-34s W = %-42s attacks = %-36s oracle calls = %d'
          % (label, fam(W), fam(H), calls))
    if verbose:
        for T, stops, g, trace in log:
            if stops is None:
                print('      candidate %-30s achieves' % fam([frozenset(T)]))
            else:
                print('      candidate %-30s fails (%s), stops = %s'
                      % (fam([frozenset(T)]), g, '{' + ', '.join(sorted(stops)) + '}'))
                for kind, sid, msg in trace:
                    arrow = '->' if kind == 'send' else '<-'
                    print('          %-4s %s %s' % (sid, arrow, show(msg)))
    return W, H


def contains_member(E, F):
    return any(e <= E for e in F)


def pair_report(title, tagged):
    print('=' * 100)
    print(title)
    s1, s2 = p1_strands(tagged), p2_strands(tagged)
    g1, g2 = ('chi1', chi1_fails), ('chi2', chi2_fails)
    W1, H1 = run('P1 alone, chi1', s1, [g1])
    W2, H2 = run('P2 alone, chi2', s2, [g2])
    J = join(W1, W2)
    print('  %-34s     %s' % ('join W(P1,chi1) v W(P2,chi2)', fam(J)))
    Wc1, Hc1 = run('P1 || P2, chi1 alone', s1 + s2, [g1])
    Wc2, Hc2 = run('P1 || P2, chi2 alone', s1 + s2, [g2])
    Wc, Hc = run('P1 || P2, chi1 & chi2', s1 + s2, [g1, g2])
    print('  check Corollary: W(chi1) v W(chi2) in composition = %s' % fam(join(Wc1, Wc2)))
    union = minimalize(H1 + H2)
    bad = [E for E in Hc if not contains_member(E, union)]
    exact = set(map(frozenset, Wc)) == set(map(frozenset, J))
    print('  Theorem condition (every composed attack contains a component attack): %s'
          % ('holds' if not bad else 'fails; offending stopping sets ' + fam(bad)))
    print('  W(composition) == join: %s' % exact)
    # cross-protocol attacks per goal: composed minimal attacks with no component member inside
    for gl, Hg, Hcomp in (('chi1', H1, Hc1), ('chi2', H2, Hc2)):
        extra = [E for E in Hcomp if not contains_member(E, Hg)]
        if extra:
            print('  cross-protocol stopping sets on %s: %s' % (gl, fam(extra)))
    return dict(W1=W1, W2=W2, J=J, Wc=Wc, Wc1=Wc1, Wc2=Wc2, Hc=Hc, exact=exact)


if __name__ == '__main__':
    print('U =', U)
    r1 = pair_report('PAIR 1: tagged formats (sig(sk_A,<cr,N,A,B>) vs sig(sk_A,<att,M,A,B>))', True)
    r2 = pair_report('PAIR 2: untagged, shared sk_A (sig(sk_A,<N,A,B>) vs sig(sk_A,<M,A,B>))', False)
