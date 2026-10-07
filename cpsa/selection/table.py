"""Print the MANIFEST.md result tables and per-row goal listings from results/*.json.

    python3 table.py rows        # results table for the CPSA rows in ../protocols
    python3 table.py cands       # same for excluded candidates and diagnostics
    python3 table.py goals       # per-row U and verbatim defgoal
"""
import json, os, sys
import templates

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, 'results')
ROWS = ['pkinit-flawed', 'pkinit-fix2', 'yahalom', 'otway-rees', 'denning-sacco', 'kerberos',
        'neuman-stubblebine', 'isoreject', 'isofix', 'blanchet', 'blanchet-fixed']
CANDS = ['woolam', 'wide-mouth-frog', 'iso-unilateral', 'kerberos-sortrule', 'kerberos-key',
         'otway-rees-neq']


def fam(F):
    if not F:
        return 'false'
    return ', '.join('{' + ', '.join(s) + '}' for s in F)


def row(name):
    r = json.load(open(os.path.join(RES, name + '.json')))
    L = r['lattice']
    U = ', '.join(r['U'])
    warn = sorted({w for p in L['points'] for w in p.get('warnings', [])})
    if not L['all_complete']:
        n_to = sum(1 for p in L['points'] if p['timeout'])
        return (f"| {name} | {len(r['U'])} | {U} | {L['n_points']} | incomplete: {n_to} timeouts | "
                f"| {L['total_time']:.2f} / {L['max_time']:.2f} | {'; '.join(warn)} | | |")
    W, A = L['W'], L['A']
    N = len(W) + len(A) if W else len(A)
    out = []
    for m in ('ref_as_found', 'fixed_as_found', 'fixed_shrink'):
        x = r.get('loop_' + m, {})
        if 'error' in x:
            out.append('error')
        else:
            out.append(f"{'=' if x['agrees'] else 'WRONG ' + fam(x['W'])} "
                       f"{x['distinct_calls']} ({x['cpsa_goal_runs']}g+{x['cpsa_replay_runs']}r)")
    return (f"| {name} | {len(r['U'])} | {U} | {L['n_points']} | {fam(W)} | {len(A)} / {N} | "
            f"{L['total_time']:.2f} / {L['max_time']:.2f} | {'; '.join(warn) or 'none'} | "
            + ' | '.join(out) + ' |')


HEADER = ("| row | \\|U\\| | U | points | W(chi) (exhaustive) | \\|A\\| / N | CPSA s total / max | "
          "warnings | ref loop | fixed loop | fixed loop, shrink |\n"
          "|---|---|---|---|---|---|---|---|---|---|---|")


def goals():
    for n in ROWS:
        t = templates.load(n)
        print(f"### {n}\n")
        for k in ('source', 'goal', 'note'):
            for v in t.meta.get(k, []):
                print(f"- {k}: {v}")
        print("- U: " + '; '.join(f"`{a}` = `{f}`" for a, f in t.U.items()))
        print("\n```scheme\n" + t.goal_text.strip() + "\n```\n")


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'rows'
    if what == 'goals':
        goals()
    else:
        print(HEADER)
        for n in (ROWS if what == 'rows' else CANDS):
            if os.path.exists(os.path.join(RES, n + '.json')):
                print(row(n))
