"""Bounded Dolev-Yao achievement oracle for NSPK / NSL, feeding the CEGIS loop.

Model. The intruder is the network: honest sends publish to its knowledge K; every honest
receive is supplied by the intruder from anything derivable from K (dy.derivable). Strands are
a fixed bounded pool. Trust is a set of Non(sk_X) assumptions: assuming Non(sk_X) keeps sk_X out
of the intruder's initial knowledge. (Freshness/Unq is not tuned here: the goal is non-injective
agreement, for which freshness is irrelevant; all nonces are fresh atoms.)

Goal (responder non-injective agreement): whenever the test strand Resp(B,A) completes, some
Init(A,B) strand has completed agreeing on (Na,Nb). An attack is a reachable state where Resp(B,A)
completed with no such matching Init(A,B).

achieve(proto, tau) -> None if the goal holds under tau, else (trace, stops) where stops is the
defence set of the attack found: the Non(sk_X) assumptions that, added, break that very run.
"""

from dy import name, pair, enc, derivable

PRINCIPALS = ['A', 'B', 'I']

def pk(x): return name('pk_' + x)
def sk(x): return name('sk_' + x)

def _var(sid, label): return ('var', sid, label)

# ---- protocol step builders -------------------------------------------------
# A strand = list of ('send'|'recv', term). self is the first param.

def init_steps(sid, a, b, nsl):
    Na = name('Na_%d' % sid)          # initiator's own fresh nonce
    Nb = _var(sid, 'Nb')              # learned in step 2
    body2 = pair(Na, pair(Nb, name(b))) if nsl else pair(Na, Nb)
    return ('Init', a, b, [
        ('send', enc(pk(b), pair(Na, name(a)))),
        ('recv', enc(pk(a), body2)),
        ('send', enc(pk(b), Nb)),
    ], {'Na': Na})

def resp_steps(sid, b, a, nsl):
    Na = _var(sid, 'Na')             # learned in step 1
    Nb = name('Nb_%d' % sid)         # responder's own fresh nonce
    body2 = pair(Na, pair(Nb, name(b))) if nsl else pair(Na, Nb)
    return ('Resp', b, a, [
        ('recv', enc(pk(b), pair(Na, name(a)))),
        ('send', enc(pk(a), body2)),
        ('recv', enc(pk(b), Nb)),
    ], {'Nb': Nb})

def scenario(nsl):
    """Fixed bounded pool: honest A->B, decoy A->I, and the test responder B expecting A."""
    return [
        init_steps(0, 'A', 'B', nsl),   # honest matching initiator (its presence = no attack)
        init_steps(1, 'A', 'I', nsl),   # A talking to the intruder (the Lowe oracle)
        resp_steps(2, 'B', 'A', nsl),   # test strand: B believes it ran with A
    ]

# ---- term instantiation -----------------------------------------------------

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

# ---- the search -------------------------------------------------------------

def initial_knowledge(tau):
    """Intruder knows all public keys, all names, its own sk_I, and every uncompromised-...
    NO: every key NOT protected by a Non assumption in tau."""
    K = {name(p) for p in PRINCIPALS}
    for p in PRINCIPALS:
        K.add(pk(p))
    K.add(sk('I'))                                  # intruder identity
    for p in ('A', 'B'):
        if ('Non', 'sk_' + p) not in tau:
            K.add(sk(p))                            # compromised
    return frozenset(K)

def pool_atoms(strands):
    atoms = {name(p) for p in PRINCIPALS}
    for role, a, b, steps, own in strands:
        for v in own.values():
            atoms.add(v)
    return sorted(atoms)                            # fixed order: deterministic search

def matching_init_done(strands, pos, binding):
    """Is there a completed Init(A,B) whose Na,Nb equal the test responder's?"""
    # test responder is strand 2
    rNa = binding.get(_var(2, 'Na')); rNb = strands[2][4]['Nb']
    for sid in (0,):                                # Init(A,B) is strand 0
        role, a, b, steps, own = strands[sid]
        if pos[sid] == len(steps) and a == 'A' and b == 'B':
            iNa = own['Na']; iNb = binding.get(_var(sid, 'Nb'))
            if iNa == rNa and iNb == rNb:
                return True
    return False

def achieve(nsl, tau, want_trace=False):
    """Return None if goal holds under tau; else (trace, stops)."""
    strands = scenario(nsl)
    K0 = initial_knowledge(tau)
    pool = pool_atoms(strands)
    start = (tuple(0 for _ in strands), K0, frozenset())
    seen = set()
    stack = [(start, [])]
    while stack:
        (pos, K, binding), trace = stack.pop()
        key = (pos, K, binding)
        if key in seen:
            continue
        seen.add(key)
        bd = dict(binding)
        # attack check: test strand complete, no matching honest initiator
        if pos[2] == 3 and not matching_init_done(strands, pos, bd):
            stops = _stops(strands, trace, K0, tau)
            return (trace, stops)
        # expand
        for sid, (role, a, b, steps, own) in enumerate(strands):
            if pos[sid] >= len(steps):
                continue
            kind, term = steps[pos[sid]]
            if kind == 'send':
                msg = inst(term, bd)
                nK = K | {msg}
                npos = tuple(p + 1 if i == sid else p for i, p in enumerate(pos))
                stack.append(((npos, nK, binding), trace + [('send', sid, msg)]))
            else:  # recv: intruder supplies a derivable matching message
                fvs = set(); free_vars(term, bd, fvs)
                for assign in _assignments(sorted(fvs), pool):
                    nb = dict(bd); nb.update(assign)
                    msg = inst(term, nb)
                    if ('var' in _flatten_heads(msg)):
                        continue
                    if derivable(set(K), msg):
                        npos = tuple(p + 1 if i == sid else p for i, p in enumerate(pos))
                        stack.append(((npos, K, frozenset(nb.items())),
                                      trace + [('recv', sid, msg)]))
    return None

def _flatten_heads(t):
    if t[0] == 'var':
        return {'var'}
    if t[0] in ('pair', 'enc', 'sig'):
        return _flatten_heads(t[1]) | _flatten_heads(t[2])
    return {t[0]}

def _assignments(vs, pool):
    if not vs:
        yield {}; return
    head, rest = vs[0], vs[1:]
    for val in pool:
        for tail in _assignments(rest, pool):
            d = {head: val}; d.update(tail); yield d

def _stops(strands, trace, K0, tau):
    """Defence set of this attack: the Non(sk_X) whose addition breaks this very run."""
    stops = set()
    for p in ('A', 'B'):
        assumption = ('Non', 'sk_' + p)
        if assumption in tau:
            continue                       # already assumed; not a candidate defence
        if sk(p) not in K0:
            continue                       # not compromised in this run anyway
        # replay the trace without sk(p) in the intruder's knowledge
        K = set(K0) - {sk(p)}
        broke = False
        for (kind, sid, msg) in trace:
            if kind == 'send':
                K.add(msg)
            else:
                if not derivable(K, msg):  # intruder could not supply this step
                    broke = True; break
        if broke:
            stops.add(assumption)
    return stops
