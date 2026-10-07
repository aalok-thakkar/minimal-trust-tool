"""Differential driver for the bounded analyser: the Python reference side.

For every protocol row the Python prototype supports, prints
  TRUST <row> <mode> <trust> <result> <states>
for every trust of 2^U (result: ACH, or the stopping set of the witness; states: distinct
states the search expanded, or - where the Python engine does not deduplicate states the
same way), and
  LOOP <row> <mode> <shrink> <W> <H> <distinct> <queries> <shrink_calls>
for Algorithm 1 (cegis.weakest) over that oracle. test/diff_bounded.ml prints the same
lines from the OCaml library; test/diff_bounded.sh compares them.

The reference files are not modified: cr.py and analyzer.py are loaded from source with
one counter added where a state enters the visited set.
Usage: python3 diff_bounded.py ARTIFACT_DIR
"""
import sys
import types
from itertools import combinations

ART = sys.argv[1]
sys.path.insert(0, ART)


def load(name, patches):
    path = '%s/%s.py' % (ART, name)
    src = open(path).read()
    for old, new in patches:
        assert old in src, (name, old)
        src = src.replace(old, new)
    mod = types.ModuleType(name)
    mod.__file__ = path
    mod.STATES = [0]
    sys.modules[name] = mod
    exec(compile(src, path, 'exec'), mod.__dict__)
    return mod


analyzer = load('analyzer', [('seen.add(key)', 'seen.add(key); STATES[0] += 1')])
cr = load('cr', [('seen.add(state)', 'seen.add(state); STATES[0] += 1')])
import channels  # noqa: E402
import composition  # noqa: E402
from cegis import weakest  # noqa: E402


def atom(a):
    return a if isinstance(a, str) else '%s(%s)' % a


def fmt_set(s):
    return '{' + ','.join(sorted(atom(a) for a in s)) + '}'


def fmt_fam(F):
    F = sorted((sorted(atom(a) for a in s) for s in F), key=lambda s: (len(s), s))
    return '[' + ';'.join('{' + ','.join(s) + '}' for s in F) + ']'


def subsets(U):
    for r in range(len(U) + 1):
        for S in combinations(U, r):
            yield set(S)


def emit_row(row, mode, U, achieve, counted):
    """achieve(tau) -> None or stops."""
    for tau in subsets(U):
        st = None
        if counted is not None:
            counted.STATES[0] = 0
        r = achieve(tau)
        if counted is not None:
            st = counted.STATES[0]
        print('TRUST %s %s %s %s %s' % (row, mode, fmt_set(tau),
                                       'ACH' if r is None else fmt_set(r),
                                       '-' if st is None else st))
    for shrink in (False, True):
        W, H, s = weakest(lambda t: achieve(set(t)), U=U, shrink=shrink)
        print('LOOP %s %s %s %s %s %d %d %d' % (row, mode, 'shrink' if shrink else 'plain',
                                                fmt_fam(W), fmt_fam(H), s['distinct'],
                                                s['total'], s['shrink']))
    sys.stdout.flush()


# challenge-response rows
for row, proto in (('signed_cr', 'signed'), ('two_key', 'twokey'),
                   ('signed_nonames', 'signed_nonames'), ('shared_nonames', 'shared_nonames')):
    U = cr.universe_U(proto)
    for mode, minimal in (('pruned', True), ('as_found', False)):
        def ach(tau, proto=proto, minimal=minimal):
            r = cr.achieve(proto, tau, minimal_run=minimal)
            return None if r is None else r[1]
        emit_row(row, mode, U, ach, cr)

# Needham-Schroeder (analyzer.py)
for row, nsl in (('nspk', False), ('nsl', True)):
    def ach(tau, nsl=nsl):
        r = analyzer.achieve(nsl, tau)
        return None if r is None else r[1]
    emit_row(row, 'as_found', [('Non', 'sk_A'), ('Non', 'sk_B')], ach, analyzer)

# channels.py (least witnesses; enumerates traces, so no state counts)
for row, nsl, U, hj in (('nspk_keys_least', False, channels.U_KEYS, False),
                        ('nsl_keys_least', True, channels.U_KEYS, False),
                        ('nspk_channels', False, channels.U_FULL, False),
                        ('nsl_channels', True, channels.U_FULL, False),
                        ('nspk_channels_hijack', False, channels.U_FULL, True),
                        ('nsl_channels_hijack', True, channels.U_FULL, True)):
    def ach(tau, nsl=nsl, U=U, hj=hj):
        r = channels.achieve(nsl, tau, U, hj)
        return None if r is None else r[1]
    emit_row(row, 'least', U, ach, None)

# composition.py (least witnesses)
for variant, tagged in (('tagged', True), ('untagged', False)):
    s1, s2 = composition.p1_strands(tagged), composition.p2_strands(tagged)
    g1, g2 = ('chi1', composition.chi1_fails), ('chi2', composition.chi2_fails)
    for pname, strands, gname, goals in (('P1', s1, 'chi1', [g1]), ('P2', s2, 'chi2', [g2]),
                                         ('P1||P2', s1 + s2, 'chi1', [g1]),
                                         ('P1||P2', s1 + s2, 'chi2', [g2]),
                                         ('P1||P2', s1 + s2, 'chi1&chi2', [g1, g2])):
        row = 'compose_%s_%s_%s' % (variant, pname, gname)
        def ach(tau, strands=strands, goals=goals):
            r = composition.oracle(strands, goals, tau)
            return None if r is None else r[0]
        emit_row(row, 'least', composition.U, ach, None)
