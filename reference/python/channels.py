"""NSPK / NSL with Kamil-Lowe channel generators in the trust universe.

Puts channel assumptions into U for Needham-Schroeder and run the
loop of Algorithm 1. Self-contained copy of the analyzer.py protocol model (same bounded pool,
same goal), extended with channels; analyzer.py itself is not modified.

Channels. A channel is a directed pair of principals (sender, receiver). Every protocol message
travels on the channel from its sender to its intended receiver as the role sees them:
  Init(a,b): sends msg 1 and msg 3 on (a,b), receives msg 2 on (b,a)
  Resp(b,a): receives msg 1 and msg 3 on (a,b), sends msg 2 on (b,a)
Generators exist only for channels between honest principals, (A,B) and (B,A). A channel with
the intruder I at one end carries no assumption: I is a legitimate endpoint there, so it reads
what is sent to it and sends what it likes as itself, and no channel level can say otherwise.

Generators (U):
  Non(sk_A), Non(sk_B)     sk_X is not in the intruder's initial knowledge
  auth(c)                  intruder cannot inject on c: every reception on c is a message that
                           the claimed sender earlier sent on c (replay of such a message is
                           allowed; the goal is non-injective)
  conf(c)                  intruder does not hear c: messages sent on c are not added to its
                           knowledge; they can still be delivered to the receiver on c

Transitions of the intruder-as-network model:
  honest send of m on c      record (c,m) as sent; unless conf(c), intruder learns m
  delivery of m on c         allowed if (c,m) was sent (honest transmission, no intruder action)
  injection of m on c        allowed if m is derivable from intruder knowledge, unless auth(c)
  [hijack=True only]         a message sent on any channel c' may be delivered on c without the
                             intruder learning it (Kamil-Lowe re-ascribe/redirect), unless auth(c)

stops(x). For an attack trace x found under trust tau, let U' = U minus tau and
D = { S subset of U' : x is still a valid run under tau + S }. D is a down-set. Each maximal
M in D is one bundle of x (one way the intruder realises the receptions), and that bundle is
removed exactly by the atoms U' minus M. When D has a single maximal element this is the
per-atom check "assuming a alone rules out x"; when it has several, the trace is several
bundles with separate clauses (separable stopping, A6) and we return the smallest clause. The oracle
returns, over all attack traces in the bounded pool, a clause that is subset-minimal.
"""

from functools import lru_cache
from itertools import combinations

from dy import name, pair, enc, derivable

PRINCIPALS = ['A', 'B', 'I']
HONEST_CHANNELS = [('A', 'B'), ('B', 'A')]

NON = [('Non', 'sk_A'), ('Non', 'sk_B')]
CHAN = [(lvl, '%s->%s' % c) for c in HONEST_CHANNELS for lvl in ('auth', 'conf')]
U_KEYS = NON
U_FULL = NON + CHAN


def pk(x): return name('pk_' + x)
def sk(x): return name('sk_' + x)
def _var(sid, label): return ('var', sid, label)
def chname(c): return '%s->%s' % c


# ---- protocol (copied from analyzer.py, steps annotated with channels) ------

def init_steps(sid, a, b, nsl):
    Na = name('Na_%d' % sid)
    Nb = _var(sid, 'Nb')
    body2 = pair(Na, pair(Nb, name(b))) if nsl else pair(Na, Nb)
    return ('Init', a, b, [
        ('send', (a, b), enc(pk(b), pair(Na, name(a)))),
        ('recv', (b, a), enc(pk(a), body2)),
        ('send', (a, b), enc(pk(b), Nb)),
    ], {'Na': Na})


def resp_steps(sid, b, a, nsl):
    Na = _var(sid, 'Na')
    Nb = name('Nb_%d' % sid)
    body2 = pair(Na, pair(Nb, name(b))) if nsl else pair(Na, Nb)
    return ('Resp', b, a, [
        ('recv', (a, b), enc(pk(b), pair(Na, name(a)))),
        ('send', (b, a), enc(pk(a), body2)),
        ('recv', (a, b), enc(pk(b), Nb)),
    ], {'Nb': Nb})


def scenario(nsl):
    """Same bounded pool as analyzer.py: honest Init(A,B), decoy Init(A,I), test Resp(B,A)."""
    return [
        init_steps(0, 'A', 'B', nsl),
        init_steps(1, 'A', 'I', nsl),
        resp_steps(2, 'B', 'A', nsl),
    ]


def inst(t, binding):
    if t[0] == 'var':
        return binding.get(t, t)
    if t[0] in ('pair', 'enc', 'sig'):
        return (t[0], inst(t[1], binding), inst(t[2], binding))
    return t


def free_vars(t, binding, acc):
    if t[0] == 'var':
        if t not in binding:
            acc.add(t)
    elif t[0] in ('pair', 'enc', 'sig'):
        free_vars(t[1], binding, acc); free_vars(t[2], binding, acc)


def _assignments(vs, pool):
    if not vs:
        yield {}; return
    for val in pool:
        for tail in _assignments(vs[1:], pool):
            d = {vs[0]: val}; d.update(tail); yield d


@lru_cache(maxsize=None)
def _der(K, m):
    return derivable(set(K), m)


# ---- model ------------------------------------------------------------------

def initial_knowledge(tau):
    K = {name(p) for p in PRINCIPALS} | {pk(p) for p in PRINCIPALS} | {sk('I')}
    for p in ('A', 'B'):
        if ('Non', 'sk_' + p) not in tau:
            K.add(sk(p))
    return frozenset(K)


def has(tau, lvl, c):
    return (lvl, chname(c)) in tau


def can_receive(tau, K, sent, c, m, hijack):
    if (c, m) in sent:
        return True                                   # honest delivery on c
    if has(tau, 'auth', c):
        return False                                  # no injection, no re-ascription onto c
    if _der(K, m):
        return True                                   # injection of a derivable message
    if hijack and any(m2 == m for (_, m2) in sent):
        return True                                   # opaque re-ascribe/redirect
    return False


def do_send(tau, K, c, m):
    return K if has(tau, 'conf', c) else K | {m}


def matching_init_done(strands, pos, bd):
    rNa = bd.get(_var(2, 'Na')); rNb = strands[2][4]['Nb']
    role, a, b, steps, own = strands[0]
    return (pos[0] == len(steps) and own['Na'] == rNa
            and bd.get(_var(0, 'Nb')) == rNb)


def attack_traces(nsl, tau, hijack=False):
    """All attack traces (as tuples of events) in the bounded pool under trust tau."""
    strands = scenario(nsl)
    pool = sorted({name(p) for p in PRINCIPALS} |
                  {v for s in strands for v in s[4].values()})
    out = []

    def dfs(pos, K, sent, bd, trace):
        if pos[2] == 3:
            if not matching_init_done(strands, pos, bd):
                out.append(tuple(trace))
            return
        for sid, (role, a, b, steps, own) in enumerate(strands):
            if pos[sid] >= len(steps):
                continue
            kind, c, term = steps[pos[sid]]
            npos = tuple(p + 1 if i == sid else p for i, p in enumerate(pos))
            if kind == 'send':
                m = inst(term, bd)
                dfs(npos, do_send(tau, K, c, m), sent | {(c, m)}, bd,
                    trace + [('send', sid, c, m)])
            else:
                fvs = set(); free_vars(term, bd, fvs)
                for asg in _assignments(sorted(fvs), pool):
                    nb = dict(bd); nb.update(asg)
                    m = inst(term, nb)
                    if can_receive(tau, K, sent, c, m, hijack):
                        dfs(npos, K, sent, nb, trace + [('recv', sid, c, m)])

    dfs((0, 0, 0), initial_knowledge(tau), frozenset(), {}, [])
    return out


def valid(trace, tau, hijack=False):
    """Is this event sequence a run of the model restricted by tau?"""
    K = initial_knowledge(tau); sent = frozenset()
    for kind, sid, c, m in trace:
        if kind == 'send':
            K = do_send(tau, K, c, m); sent = sent | {(c, m)}
        elif not can_receive(tau, K, sent, c, m, hijack):
            return False
    return True


def clauses(trace, tau, U, hijack=False):
    """Clauses of the bundles of this trace: U' minus M for each maximal surviving M."""
    Up = [a for a in U if a not in tau]
    D = [frozenset(S) for r in range(len(Up) + 1) for S in combinations(Up, r)
         if valid(trace, set(tau) | set(S), hijack)]
    maxs = [M for M in D if not any(M < M2 for M2 in D)]
    return [frozenset(Up) - M for M in maxs]


STATS = {'nonprincipal': 0}


def achieve(nsl, tau, U, hijack=False):
    """None if tau achieves responder agreement in the bounded pool; else (trace, stops) with
    stops subset-minimal among the clauses of all attack bundles."""
    best = None
    for tr in attack_traces(nsl, tau, hijack):
        cl = clauses(tr, tau, U, hijack)
        if len(cl) > 1:
            STATS['nonprincipal'] += 1
        for s in cl:
            if best is None or len(s) < len(best[1]):
                best = (tr, s)
        if best is not None and len(best[1]) == 0:
            break
    return best


# ---- driver -----------------------------------------------------------------

def show(a):
    return '%s(%s)' % a


def fmt_family(F):
    if not F:
        return '[]  (false: no trust suffices)'
    return '[' + ', '.join('{' + ', '.join(sorted(show(a) for a in T)) + '}' for T in F) + ']'


def fmt_trace(tr):
    def t(m):
        if m[0] == 'name': return m[1]
        if m[0] == 'pair': return '%s,%s' % (t(m[1]), t(m[2]))
        if m[0] == 'enc':  return '{%s}%s' % (t(m[2]), t(m[1]))
        return str(m)
    names = ['Init(A,B)', 'Init(A,I)', 'Resp(B,A)']
    return '\n'.join('    %-4s %-9s on %s: %s' % (k, names[s], chname(c), t(m))
                     for k, s, c, m in tr)


def run(nsl, U, hijack=False, verbose=True):
    from cegis import cegis
    calls, distinct, log = [0], {}, []

    def oracle(tau):
        calls[0] += 1
        key = frozenset(tau)
        if key not in distinct:
            distinct[key] = achieve(nsl, set(tau), U, hijack)
            r = distinct[key]
            log.append((key, None if r is None else r[1], None if r is None else r[0]))
        r = distinct[key]
        return None if r is None else r[1]

    W, H = cegis(oracle)
    if verbose:
        for T, s, tr in log:
            print('  O({%s}) = %s' % (', '.join(sorted(show(a) for a in T)),
                  'achieves' if s is None else 'fails, stops = {%s}' %
                  ', '.join(sorted(show(a) for a in s))))
    return W, H, calls[0], len(distinct), log


def brute(nsl, U, hijack=False):
    """Achievement at every point of 2^U; minimal sufficient trusts (cross-check)."""
    suff = [frozenset(S) for r in range(len(U) + 1) for S in combinations(U, r)
            if achieve(nsl, set(S), U, hijack) is None]
    return [S for S in suff if not any(T < S for T in suff)]


def main():
    from hitting import blocker
    for label, nsl, U, hj in [
        ('NSPK, U = keys (Table 2 row, regression)', False, U_KEYS, False),
        ('NSL,  U = keys (Table 2 row, regression)', True, U_KEYS, False),
        ('NSPK, U = keys + channels', False, U_FULL, False),
        ('NSL,  U = keys + channels', True, U_FULL, False),
        ('NSPK, U = keys + channels, hijack variant', False, U_FULL, True),
    ]:
        print('==', label)
        print('   U =', ', '.join(show(a) for a in U))
        W, H, calls, dist, log = run(nsl, U, hj)
        bf = brute(nsl, U, hj)
        print('   H(chi) =', fmt_family(H))
        print('   W(chi) =', fmt_family(W))
        print('   oracle calls: %d total, %d distinct' % (calls, dist))
        ok = set(map(frozenset, W)) == set(bf)
        print('   brute force over 2^%d trusts agrees: %s' % (len(U), ok))
        print('   blocker(blocker(W)) == H: %s' %
              (set(map(frozenset, blocker(blocker(H)))) == set(map(frozenset, H))))
        r = achieve(nsl, set(NON), U, hj)
        if r is None:
            print('   under {Non(sk_A), Non(sk_B)}: achieves')
        else:
            print('   witness under {Non(sk_A), Non(sk_B)}, stops = {%s}:' %
                  ', '.join(sorted(show(a) for a in r[1])))
            print(fmt_trace(r[0]))
        print()
    print('traces with several bundles (non-principal D):', STATS['nonprincipal'])


if __name__ == '__main__':
    main()
