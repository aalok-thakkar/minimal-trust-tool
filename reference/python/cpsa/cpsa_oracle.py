"""CPSA 4 as the achievement oracle of Algorithm 1, with stops(x) computed from CPSA output.

oracle(T):
  1. Put the trust T into the hypothesis of a CPSA goal and run cpsa4 (one "goal call").
  2. If no shape reports (satisfies (no ...)), T achieves the goal: return None.
  3. Otherwise each shape x reporting (satisfies (no ... bindings)) is a counterexample.
     Compute stops(x) by re-checking x's own skeleton with assumptions added
     (one "check call" per atom of U \\ T, per shape):
        survives(x, M)  iff  CPSA reports skeleton(x) + M as realized.
     Greedy: M := {}; for a in U \\ T: if survives(x, M + {a}) then M := M + {a}.
     stops(x) := (U \\ T) \\ M.
     Every trust disjoint from stops(x) is contained in T + M, under which x survives,
     so stops(x) is a genuine conflict whatever x is. When x's survival is decided
     atom by atom (survives(x, M) iff survives(x, {a}) for all a in M), the greedy result
     equals { a : not survives(x, {a}) }, the per-atom stopping set of Definition 10.
  4. Return a subset-minimal stops(x) among the counterexample shapes of this run.

An atom is a CPSA goal fact over the goal's universally quantified variables, e.g.
"(non (privk as))" or "(uniq n-b)". To add it to the shape, the goal variables are
instantiated with the shape terms CPSA prints in the (satisfies (no ...)) binding list,
then "(non t)" goes into the skeleton's non-orig list and "(uniq t)" into uniq-orig.

The CPSA binary is $CPSA4, else `cpsa4` on PATH, else ~/.local/bin/cpsa4.
"""

import os, re, shutil, subprocess, tempfile, time

CPSA = (os.environ.get("CPSA4") or shutil.which("cpsa4")
        or os.path.expanduser("~/.local/bin/cpsa4"))
CPSA_OPTS = []          # defaults: step limit 2000, strand bound 12 (see README.md)


# ---- S-expressions -----------------------------------------------------------

_TOK = re.compile(r'\s*(?:(;[^\n]*)|(\()|(\))|("(?:[^"\\]|\\.)*")|([^\s()";]+))')

def parse_all(text):
    out, stack, pos = [], [[]], 0
    while pos < len(text):
        m = _TOK.match(text, pos)
        if not m or m.end() == pos:
            if text[pos:].strip() == '':
                break
            raise ValueError(f"bad sexp at {pos}: {text[pos:pos+40]!r}")
        pos = m.end()
        com, lp, rp, st, at = m.groups()
        if com:
            continue
        if lp:
            stack.append([])
        elif rp:
            top = stack.pop(); stack[-1].append(top)
        elif st is not None:
            stack[-1].append(st)
        elif at is not None:
            stack[-1].append(at)
    return stack[0]

def show(s):
    return '(' + ' '.join(show(x) for x in s) + ')' if isinstance(s, list) else s

def field(form, key):
    """All sub-forms of `form` whose head is `key`."""
    return [x for x in form if isinstance(x, list) and x and x[0] == key]

def subst(s, env):
    if isinstance(s, list):
        return [subst(x, env) for x in s]
    return env.get(s, s)


# ---- running CPSA ------------------------------------------------------------

class Stats:
    def __init__(self):
        self.goal_calls = 0; self.check_calls = 0
        self.goal_time = 0.0; self.check_time = 0.0
        self.log = []

def run_cpsa(src):
    with tempfile.NamedTemporaryFile('w', suffix='.scm', delete=False) as f:
        f.write(src); path = f.name
    t0 = time.time()
    p = subprocess.run([CPSA] + CPSA_OPTS + [path], capture_output=True, text=True,
                       timeout=600)
    dt = time.time() - t0
    os.unlink(path)
    return p.stdout, p.stderr, dt

def skeletons(out):
    return [f for f in parse_all(out) if isinstance(f, list) and f and f[0] == 'defskeleton']

def incomplete(out):
    """CPSA stops early when it hits the step limit or strand bound; then 'no counterexample
    found' is not a proof. We refuse to treat such a run as an answer."""
    return ('Nothing left to do' not in out or 'aborting run' in out)


# ---- the oracle --------------------------------------------------------------

class CPSAOracle:
    """proto: CPSA defprotocol text. U: dict name -> goal fact text over goal variables.
    goal(T_facts): function returning the defgoal text with the given hypothesis facts."""

    def __init__(self, name, proto, U, goal, verbose=True):
        self.name, self.proto, self.U, self.goal = name, proto, U, goal
        self.stats = Stats(); self.verbose = verbose
        self.cache = {}

    def _say(self, msg):
        self.stats.log.append(msg)
        if self.verbose:
            print(msg)

    def achieves(self, T):
        """Plain achievement check (no stops computation)."""
        return self._goal_run(T)[0]

    def _goal_run(self, T):
        T = frozenset(T)
        src = (f'(herald "{self.name} mintrust")\n' + self.proto +
               self.goal([self.U[a] for a in sorted(T)]))
        out, err, dt = run_cpsa(src)
        self.stats.goal_calls += 1; self.stats.goal_time += dt
        if err.strip() or incomplete(out):
            raise RuntimeError(f"CPSA failed or incomplete on T={sorted(T)}:\n{err}\n{out[-2000:]}")
        shapes = [s for s in skeletons(out) if field(s, 'shape')]
        bad = []
        for s in shapes:
            for sat in field(s, 'satisfies'):
                if isinstance(sat[1], list) and sat[1][0] == 'no':
                    bad.append((s, sat[1]))
        ok = not bad          # no shape violates the goal (vacuous if no shapes)
        return ok, bad, dt, len(shapes)

    def survives(self, shape, binding, atoms):
        """Is the realized shape still realized when `atoms` are assumed as well?
        One CPSA call on the shape's own skeleton plus the atoms."""
        env = {}
        for b in binding[1:]:
            if isinstance(b, list) and len(b) == 2 and isinstance(b[0], str):
                env[b[0]] = b[1]
        extra = {}
        for atom in atoms:
            fact = subst(parse_all(self.U[atom])[0], env)
            slot = {'non': 'non-orig', 'uniq': 'uniq-orig'}[fact[0]]
            extra.setdefault(slot, []).append(fact[1])
        keep = ('vars', 'defstrand', 'deflistener', 'defstrandmax', 'precedes', 'leadsto',
                'non-orig', 'pen-non-orig', 'uniq-orig', 'uniq-gen', 'absent', 'conf',
                'auth', 'facts', 'priority')
        sk = ['defskeleton', shape[1]]
        for x in shape[2:]:
            if isinstance(x, list) and x and x[0] in keep:
                if x[0] in extra:
                    x = x + [t for t in extra.pop(x[0]) if t not in x[1:]]
                sk.append(x)
        for slot, terms in extra.items():
            sk.append([slot] + terms)
        src = '(herald "stops check")\n' + self.proto + '\n' + show(sk) + '\n'
        out, err, dt = run_cpsa(src)
        self.stats.check_calls += 1; self.stats.check_time += dt
        if err.strip():
            # CPSA rejects the skeleton as ill-formed, e.g. a uniq-orig value that does not
            # originate on a regular strand of x: x cannot satisfy the atom.
            return False, 'ill-formed: ' + err.strip().splitlines()[-1]
        sks = skeletons(out)
        first = sks[0] if sks else None
        realized = first is not None and bool(field(first, 'realized'))
        return realized, ('realized' if realized else 'unrealized')

    def __call__(self, T):
        """Algorithm 1 oracle contract: None if T achieves, else a stopping set."""
        T = frozenset(T)
        if T in self.cache:
            return self.cache[T]
        ok, bad, dt, nshapes = self._goal_run(T)
        if ok:
            self._say(f"  O({sorted(T) or '{}'}) = achieves   [{nshapes} shape(s), {dt:.2f}s]")
            self.cache[T] = None
            return None
        cands = []
        for i, (shape, binding) in enumerate(bad):
            M, why = [], {}
            for a in sorted(set(self.U) - T):
                surv, reason = self.survives(shape, binding, M + [a])
                why[a] = reason
                if surv:
                    M.append(a)
            st = set(self.U) - T - set(M)
            label = field(shape, 'label')[0][1]
            self._say(f"  O({sorted(T) or '{}'}) = fails: shape label {label}, "
                      f"stops(x) = {sorted(st) or '{}'}  checks: {why}")
            cands.append(frozenset(st))
        minimal = [s for s in cands if not any(t < s for t in cands)]
        res = sorted(minimal, key=lambda s: (len(s), sorted(s)))[0]
        self.cache[T] = set(res)
        return set(res)
