#!/usr/bin/env python3
"""Generate Table tab:scale (LaTeX) and a plain-text summary from the E3 CSVs.

    python3 scripts/scale_table.py [RESULTS_DIR]      (default: results/final)

Reads RESULTS_DIR/scale_counts.csv and scale_timing.csv written by `trust scale`.
Table rows are the groups flagged table=1 in scale_timing.csv (rule in
bin/scale_driver.ml, table_groups). Per row, over the seeds of the group: median |H|,
median and max |W|, median distinct calls, median time (per-seed median of the
repetitions), B1 calls, median B2 calls (or > 2^21 if any seed hit the budget), and
how many seeds' B3 answer is in W. Writes RESULTS_DIR/tab_scale.tex; prints the summary.
"""

import csv
import os
import statistics
import sys
from collections import defaultdict

NAMES = {
    'rand-m1': r'random, $m=n$',
    'rand-m2': r'random, $m=2n$',
    'rand-m4': r'random, $m=4n$',
    'pairs': 'disjoint pairs',
    'dual': 'dual of pairs',
    'thr': r'all $\frac{n}{2}$-sets',
    'thr-dual': r'all $(\frac{n}{2}{+}1)$-sets',
}
SHORT = False
SHORT_KEYS = [('rand-m1', 55), ('rand-m2', 70), ('rand-m4', 80), ('pairs', 24), ('dual', 22)]
ORDER = ['rand-m1', 'rand-m2', 'rand-m4', 'pairs', 'dual', 'thr', 'thr-dual']


def num(x):
    """LaTeX integer with thin-space thousands separators."""
    s = '%d' % round(x)
    out = ''
    while len(s) > 3:
        out = r'\,' + s[-3:] + out
        s = s[:-3]
    return s + out


def tsec(x):
    if x < 0.01:
        return '%.4f' % x
    if x < 1:
        return '%.3f' % x
    if x < 100:
        return '%.1f' % x
    return '%.0f' % x


def med(xs):
    return statistics.median(xs)


def main(d):
    counts = list(csv.DictReader(open(os.path.join(d, 'scale_counts.csv'))))
    timing = list(csv.DictReader(open(os.path.join(d, 'scale_timing.csv'))))
    by = defaultdict(list)                     # (family, n, method) -> rows
    for r in counts:
        by[(r['family'], int(r['n']), r['method'])].append(r)

    # ---- summary ----------------------------------------------------------
    alg1 = [r for r in counts if r['method'] == 'alg1']
    ok = [r for r in alg1 if r['status'] == 'ok']
    eq = [r for r in ok if int(r['calls']) == int(r['H']) + int(r['W'])]
    hrec = [r for r in ok if r['h_recovered'] == '1']
    print('alg1 runs: %d ok, %d not ok; distinct calls = |H|+|W| in %d/%d; H recovered in %d/%d'
          % (len(ok), len(alg1) - len(ok), len(eq), len(ok), len(hrec), len(ok)))
    for r in ok:
        if int(r['calls']) != int(r['H']) + int(r['W']):
            print('  calls != |H|+|W|:', r['family'], r['n'], r['seed'], r['calls'], r['H'], r['W'])

    # agreement of W across methods (digests)
    dg = defaultdict(dict)
    for r in counts:
        if r['status'] == 'ok' and r['w_digest']:
            dg[(r['family'], r['n'], r['m'], r['seed'])][r['method']] = r['w_digest']
    mism = [(k, v) for k, v in dg.items() if len(set(v.values())) > 1]
    print('W agreement across methods: %d instances compared, %d mismatches' % (len(dg), len(mism)))
    for k, v in mism[:10]:
        print('  mismatch', k, v)

    print('\nper family and method: largest n with every seed ok; first n with a failure')
    fams = sorted({r['family'] for r in counts}, key=lambda f: ORDER.index(f) if f in ORDER else 99)
    for f in fams:
        for meth in ['alg1', 'padded', 'padded_shrink', 'b1', 'b2', 'b3']:
            rows = [r for r in counts if r['family'] == f and r['method'] == meth]
            if not rows:
                continue
            ns = sorted({int(r['n']) for r in rows})
            full = [n for n in ns if all(r['status'] == 'ok' for r in rows if int(r['n']) == n)]
            bad = [(int(r['n']), r['status']) for r in rows if r['status'] != 'ok']
            extra = ''
            if meth == 'b2':
                inc = sorted({int(r['n']) for r in rows if r['status'] == 'ok' and r['complete'] == '0'})
                extra = '; budget hit from n=%s' % (inc[0] if inc else '-')
            if meth == 'b3':
                inw = sum(r['in_W'] == '1' for r in rows if r['status'] == 'ok')
                extra = '; answer in W in %d/%d' % (inw, sum(r['status'] == 'ok' for r in rows))
            if meth == 'padded_shrink':
                okr = [r for r in rows if r['status'] == 'ok']
                within = sum(r['within_bound'] == '1' for r in okr)
                extra = '; within |W|+|H|(1+n) in %d/%d' % (within, len(okr))
            if meth == 'padded':
                okr = [r for r in rows if r['status'] == 'ok']
                over = sum(int(r['calls']) > int(r['H']) + int(r['W']) for r in okr)
                extra = '; calls > |H|+|W| in %d/%d' % (over, len(okr))
            print('  %-9s %-14s max n ok = %-3s first failure = %s%s'
                  % (f, meth, full[-1] if full else '-',
                     ('%d (%s)' % min(bad)) if bad else '-', extra))

    # ---- table ------------------------------------------------------------
    groups = defaultdict(list)
    for r in timing:
        if r['table'] == '1':
            groups[(r['family'], int(r['n']))].append(r)
    keys = sorted(groups, key=lambda k: (ORDER.index(k[0]) if k[0] in ORDER else 99, k[1]))
    if SHORT:   # conference version: one row per family, the largest n in the timing groups
        keys = [k for k in keys if k in SHORT_KEYS]
    lines = []
    print('\ntable rows')
    for f, n in keys:
        trows = [r for r in groups[(f, n)] if r['wall_median']]
        a = [r for r in by[(f, n, 'alg1')] if r['status'] == 'ok']
        if not a:
            continue
        H = [int(r['H']) for r in a]
        W = [int(r['W']) for r in a]
        C = [int(r['calls']) for r in a]
        T = [float(r['wall_median']) for r in trows]
        b1 = [r for r in by[(f, n, 'b1')] if r['status'] == 'ok']
        b2 = [r for r in by[(f, n, 'b2')]]
        b3 = [r for r in by[(f, n, 'b3')] if r['status'] == 'ok']
        b1s = num(2 ** n) if b1 and len(b1) == len(a) else '--'
        if b2 and all(r['status'] == 'ok' and r['complete'] == '1' for r in b2):
            b2s = num(med([int(r['calls']) for r in b2]))
        elif any(r['status'] == 'ok' and r['complete'] == '0' for r in b2):
            b2s = r'$>2^{21}$'
        else:
            b2s = '--'
        b3s = '%d/%d' % (sum(r['in_W'] == '1' for r in b3), len(b3))
        seeds = len(a)
        wcol = num(med(W)) if seeds == 1 else '%s (%s)' % (num(med(W)), num(max(W)))
        lines.append('%-28s & %2d & %s & %s & %s & %s & %s & %s & %s\\\\'
                     % (NAMES.get(f, f), n, num(med(H)), wcol, num(med(C)),
                        tsec(med(T)) if T else '--', b1s, b2s, b3s))
        print('  ', f, n, 'seeds', seeds, 'H', med(H), 'W', med(W), max(W), 'calls', med(C),
              'time', med(T) if T else None, 'B1', b1s, 'B2', b2s, 'B3', b3s)

    tex = r"""\begin{table}[t]
\caption{Algorithm~1 against brute force on instances from the reduction of
the proof of Theorem~\ref{thm:cost}. Random rows aggregate ten seeds: medians, with the maximum
of $|\weakest|$ in parentheses. Calls are distinct oracle calls; in every run they
equal $|\attacks|+|\weakest|$. Time is the median wall-clock time of Algorithm~1 in
seconds (median of repetitions per seed). B1 queries all $2^n$ trusts (run for $n \le
24$); B2 enumerates trusts by size, skipping supersets of sufficient trusts found so
far, with a budget of $2^{21}$ calls; B3 is the conjunct-dropping heuristic of~\cite{rowe}, and
its column counts the seeds whose single answer is in $\weakest$.}
\label{tab:scale}
\centering
\setlength{\tabcolsep}{2.4pt}
\footnotesize
\begin{tabular}{lrrrrrrrr}
\toprule
instance & $n$ & $|\attacks|$ & $|\weakest|$ & calls & time (s) & B1 calls & B2 calls & B3\\
\midrule
""" + '\n'.join(lines) + r"""
\bottomrule
\end{tabular}
\end{table}
"""
    out = 'tab_scale_short.tex' if SHORT else 'tab_scale.tex'
    open(os.path.join(d, out), 'w').write(tex)
    print('\nwrote', os.path.join(d, out), '(%d rows)' % len(lines))


if __name__ == '__main__':
    SHORT = '--short' in sys.argv
    args = [a for a in sys.argv[1:] if a != '--short']
    main(args[0] if args else 'results/final')
