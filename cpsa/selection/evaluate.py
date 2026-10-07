"""Ground truth and reference loop runs for the CPSA protocol rows.

    python3 evaluate.py [name ...]      # default: every template in ../protocols

For each template:
  1. Lattice: run cpsa4 (defaults, no options) at every T in 2^U, 60 s timeout per run.
     A run counts only if it ends with "Nothing left to do" and reports no step-limit or
     strand-bound abort. W = minimal sufficient trusts; A = blocker(W).
  2. Loop: Algorithm 1 from reference/python/cegis.py (weakest; as-found witnesses and shrink
     mode) with two oracles: 'ref' = reference/python/cpsa/cpsa_oracle.py unchanged, 'fixed' =
     oracle_fixed.py (same, with the preskeleton correction to the replay check).
     reference/python/ is imported read-only; nothing there is modified.
Writes results/<name>.json and results/<name>.log.
"""
import itertools, json, os, re, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'reference', 'python')
sys.path.insert(0, ART); sys.path.insert(0, os.path.join(ART, 'cpsa'))

import templates
from cegis import weakest
from hitting import blocker, minimalize
from cpsa_oracle import CPSA, CPSAOracle, parse_all, skeletons, field
from oracle_fixed import FixedOracle

TIMEOUT = 60
OUT = os.path.join(HERE, 'results')
STD_COMMENTS = ('CPSA 4.4.9', 'Nothing left to do')


def cpsa_version():
    return subprocess.run([CPSA, '--version'], capture_output=True, text=True).stdout.strip()


def run_point(tpl, T):
    """One CPSA goal run at trust T (list of atom ids). Returns a record dict."""
    src = tpl.source([tpl.U[a] for a in T])
    with tempfile.NamedTemporaryFile('w', suffix='.scm', delete=False) as f:
        f.write(src); path = f.name
    t0 = time.time()
    try:
        p = subprocess.run([CPSA, path], capture_output=True, text=True, timeout=TIMEOUT)
        out, err, timeout = p.stdout, p.stderr, False
    except subprocess.TimeoutExpired:
        out, err, timeout = '', '', True
    dt = time.time() - t0
    os.unlink(path)
    rec = {'T': list(T), 'time': round(dt, 4), 'timeout': timeout}
    if timeout:
        rec.update(complete=False, verdict=None, warnings=['timeout > %d s' % TIMEOUT])
        return rec
    warnings = []
    if err.strip():
        warnings.append('stderr: ' + err.strip()[-300:])
    for m in re.finditer(r'(step limit exceeded|strand bound exceeded|aborting[^"\n]*)',
                         out, re.I):
        warnings.append(m.group(1))
    forms = parse_all(out) if not err.strip() else []
    for fm in forms:      # top-level comments other than the standard ones
        if isinstance(fm, list) and fm and fm[0] == 'comment':
            txt = ' '.join(x if isinstance(x, str) else '' for x in fm[1:]).strip('"')
            if 'All input read' not in txt and not any(s in txt for s in STD_COMMENTS):
                warnings.append('comment: ' + txt[:200])
    complete = 'Nothing left to do' in out and not any(
        'exceeded' in w.lower() or 'aborting' in w.lower() for w in warnings) and not err.strip()
    shapes = [s for s in skeletons(out) if field(s, 'shape')] if forms else []
    nbad = sum(1 for s in shapes for sat in field(s, 'satisfies')
               if isinstance(sat[1], list) and sat[1][0] == 'no')
    nskel = len(skeletons(out)) if forms else 0
    rec.update(complete=complete, verdict=(nbad == 0) if complete else None,
               shapes=len(shapes), failing_shapes=nbad, skeletons=nskel, warnings=warnings)
    return rec


def lattice(tpl, log):
    U = list(tpl.U)
    pts = []
    for r in range(len(U) + 1):
        for T in itertools.combinations(U, r):
            rec = run_point(tpl, T)
            pts.append(rec)
            log(f"  T={list(T) or '{}'}: "
                + ('TIMEOUT' if rec['timeout'] else
                   ('INCOMPLETE' if not rec['complete'] else
                    ('achieves' if rec['verdict'] else 'fails')))
                + f"  [{rec['time']:.2f}s, shapes={rec.get('shapes')}, "
                  f"skeletons={rec.get('skeletons')}]"
                + (f"  warnings={rec['warnings']}" if rec.get('warnings') else ''))
    ok = all(p['complete'] for p in pts)
    res = {'points': pts, 'n_points': len(pts), 'all_complete': ok,
           'total_time': round(sum(p['time'] for p in pts), 3),
           'max_time': round(max(p['time'] for p in pts), 3)}
    if ok:
        suff = [frozenset(p['T']) for p in pts if p['verdict']]
        # monotonicity check (A4): every superset of a sufficient trust is sufficient
        allpts = {frozenset(p['T']): p['verdict'] for p in pts}
        mono = all(allpts[T] for T in allpts if any(S <= T for S in suff))
        W = minimalize(suff)
        res.update(monotone=mono, n_sufficient=len(suff),
                   W=sorted(sorted(w, key=U.index) for w in W),
                   A=sorted(sorted(a, key=U.index) for a in blocker(W)))
    return res


def loop(tpl, log, shrink=False, cls=CPSAOracle):
    orc = cls(tpl.name, tpl.proto, tpl.U, tpl.goal, verbose=False)
    t0 = time.time()
    W, H, st = weakest(orc, U=set(tpl.U), shrink=shrink)
    wall = time.time() - t0
    for line in orc.stats.log:
        log('   ' + line)
    U = list(tpl.U)
    return {'W': sorted(sorted(w, key=U.index) for w in W),
            'H': sorted(sorted(h, key=U.index) for h in H),
            'distinct_calls': st['distinct'], 'total_calls': st['total'],
            'shrink_calls': st['shrink'],
            'cpsa_goal_runs': orc.stats.goal_calls, 'cpsa_replay_runs': orc.stats.check_calls,
            'cpsa_goal_time': round(orc.stats.goal_time, 3),
            'cpsa_replay_time': round(orc.stats.check_time, 3), 'wall': round(wall, 3)}


def evaluate(name):
    tpl = templates.load(name)
    os.makedirs(OUT, exist_ok=True)
    lines = []
    def log(s):
        print(s, flush=True); lines.append(s)
    log(f"=== {name}  U={list(tpl.U)}")
    rec = {'name': name, 'meta': tpl.meta, 'U': tpl.U, 'cpsa': cpsa_version(),
           'timeout_per_run': TIMEOUT}
    rec['lattice'] = lattice(tpl, log)
    L = rec['lattice']
    log(f"  lattice: {L['n_points']} points, {L['total_time']:.2f}s total, "
        f"max {L['max_time']:.2f}s, complete={L['all_complete']}, "
        f"W={L.get('W')}, A={L.get('A')}, monotone={L.get('monotone')}")
    if L['all_complete']:
        for orc_name, cls in (('ref', CPSAOracle), ('fixed', FixedOracle)):
          for wmode in ('as_found', 'shrink'):
            mode = orc_name + '_' + wmode
            try:
                r = loop(tpl, log, shrink=(wmode == 'shrink'), cls=cls)
                r['agrees'] = (sorted(map(sorted, r['W'])) == sorted(map(sorted, L['W'])))
                r['H_equals_A'] = (sorted(map(sorted, r['H'])) == sorted(map(sorted, L['A'])))
            except Exception as e:          # record, do not hide
                r = {'error': repr(e)[:2000]}
            rec['loop_' + mode] = r
            log(f"  loop[{mode}]: {r}")
    json.dump(rec, open(os.path.join(OUT, name + '.json'), 'w'), indent=1)
    open(os.path.join(OUT, name + '.log'), 'w').write('\n'.join(lines) + '\n')
    return rec


if __name__ == '__main__':
    for n in (sys.argv[1:] or templates.names()):
        evaluate(n)
