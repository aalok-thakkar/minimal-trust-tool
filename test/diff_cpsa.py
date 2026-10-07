"""Differential check: OCaml `trust cpsa` rows against the corrected Python reference.

    python3 test/diff_cpsa.py [results/cpsa_rows.csv] [cpsa/selection/results]

For every row of the CSV, reads <ref>/<row>.json (written by cpsa/selection/evaluate.py)
and compares: exhaustive W and A; for the fixed oracle (oracle_fixed.py) in as-found and
shrink mode: W, H, distinct calls, main-loop queries, shrink calls, CPSA goal runs and
replay runs. Exit status 1 on any disagreement or missing reference.
"""
import csv, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
rows_csv = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'results', 'cpsa_rows.csv')
ref_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'cpsa', 'selection', 'results')


def fam(s):
    if s == '[]':
        return frozenset()
    return frozenset(frozenset(x.strip('{}').split()) for x in s.split(';'))


def pyfam(l):
    return frozenset(frozenset(x) for x in l)


bad = 0
for r in csv.DictReader(open(rows_csv)):
    name = r['row']
    path = os.path.join(ref_dir, name + '.json')
    if r['error']:
        print(f'{name}: OCaml error: {r["error"]}'); bad += 1; continue
    if not os.path.exists(path):
        print(f'{name}: no Python reference at {path}'); bad += 1; continue
    ref = json.load(open(path))
    L = ref['lattice']
    checks = [('W_exh', fam(r['W_exh']), pyfam(L['W'])),
              ('A_exh', fam(r['A_exh']), pyfam(L['A'])),
              ('monotone', r['monotone'] == 'yes', L['monotone'])]
    for mode, key in (('asfound', 'loop_fixed_as_found'), ('shrink', 'loop_fixed_shrink')):
        p = ref[key]
        checks += [(f'{mode} W', fam(r[mode + '_W']), pyfam(p['W'])),
                   (f'{mode} H', fam(r[mode + '_H']), pyfam(p['H'])),
                   (f'{mode} distinct', int(r[mode + '_distinct']), p['distinct_calls']),
                   (f'{mode} queries', int(r[mode + '_queries']), p['total_calls']),
                   (f'{mode} shrink_calls', int(r[mode + '_shrink_calls']), p['shrink_calls']),
                   (f'{mode} goal runs', int(r[mode + '_goal_runs']), p['cpsa_goal_runs']),
                   (f'{mode} replay runs', int(r[mode + '_replay_runs']), p['cpsa_replay_runs'])]
    diffs = [(k, a, b) for k, a, b in checks if a != b]
    if diffs:
        bad += 1
        for k, a, b in diffs:
            print(f'{name}: {k}: OCaml {a} != Python {b}')
    else:
        print(f'{name}: agree ({len(checks)} fields)')
print('differential check:', 'all rows agree' if bad == 0 else f'{bad} row(s) disagree')
sys.exit(1 if bad else 0)
