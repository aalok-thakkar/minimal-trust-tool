#!/usr/bin/env python3
"""Generate the tables and number macros of the full-length (arXiv) evaluation.

    python3 scripts/make_tables_long.py [RESULTS_DIR] [OUT_DIR]
        RESULTS_DIR  default: results/final
        OUT_DIR      default: RESULTS_DIR/tables

Reads the CSVs, manifests and logs in RESULTS_DIR and the CPSA templates in
cpsa/protocols/. Writes into OUT_DIR only files whose names start with `long_`:

    long_rows.tex          protocol rows: U, W, |H|, agreement with exhaustive evaluation
    long_calls.tex         distinct calls per witness mode, CPSA runs, baselines
    long_cpsa_timing.tex   CPSA wall time per method, median and IQR
    long_channels.tex      NSPK/NSL with channel generators, with and without hijack
    long_bound.tex         bound sensitivity with states explored and time
    long_scale_random.tex  scale, random families, per n, aggregated over seeds
    long_scale_struct.tex  scale, structured families, per n
    long_gadget.tex        gadget check, one row per instance
    long_app_<row>.tex     appendix data per CPSA row (source, U with facts, role declarations)
    long_goal_<row>.scm    the goal of each CPSA template, verbatim
    long_numbers.tex       \\newcommand{\\numL...} macros for numbers quoted in the text

The atom notation is that of scripts/make_tables.py (imported, not modified). No number
in these files is typed by hand.
"""

import csv
import os
import re
import statistics
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from make_tables import atom_tex, parse_family, family_tex  # noqa: E402

# ---- helpers ------------------------------------------------------------------------------


def read(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def num(x):
    """Integer with thin-space thousands separators."""
    s = '%d' % round(x)
    neg = s.startswith('-')
    s = s.lstrip('-')
    out = ''
    while len(s) > 3:
        out = r'\,' + s[-3:] + out
        s = s[:-3]
    return ('-' if neg else '') + s + out


def tsec(x):
    if x == 0:
        return '0'
    if x < 0.01:
        return '%.4f' % x
    if x < 1:
        return '%.3f' % x
    if x < 100:
        return '%.1f' % x
    return '%.0f' % x


def tsec_sci(x):
    """Seconds for scale times, which range over eight orders of magnitude."""
    if x == 0:
        return '0'
    if x < 0.001:
        m, e = ('%.1e' % x).split('e')
        return r'$%s{\cdot}10^{%d}$' % (m, int(e))
    return tsec(x)


def quartiles(xs):
    xs = sorted(xs)
    if len(xs) == 1:
        return xs[0], xs[0]
    q = statistics.quantiles(xs, n=4, method='inclusive')
    return q[0], q[2]


def fam_sets(s):
    f = parse_family(s)
    return None if f is None else f


def set_tex(atoms):
    return r'\{%s\}' % ', '.join(atom_tex(a) for a in atoms)


def fam_inline(s, sep=', '):
    """A family on one line, in math mode pieces: '$\\{a\\}$, $\\{b, c\\}$' or false."""
    f = parse_family(s)
    if f is None:
        return r'$\mathsf{false}$'
    if f == [[]]:
        return r'$\{\emptyset\}$'
    return sep.join('$%s$' % set_tex(t) for t in f)


def fam_lines(s, per_line=1):
    """A family split over lines, each a string; the caller adds \\quad etc."""
    f = parse_family(s)
    if f is None:
        return [r'$\mathsf{false}$']
    if f == [[]]:
        return [r'$\{\emptyset\}$']
    items = ['$%s$' % set_tex(t) for t in f]
    lines = []
    for i in range(0, len(items), per_line):
        lines.append(', '.join(items[i:i + per_line]))
    return [l + (',' if i < len(lines) - 1 else '') for i, l in enumerate(lines)]


def u_atoms_analyser(u):
    return [a.strip() for a in u.strip('{}').split(',') if a.strip()]


def u_atoms_cpsa(u):
    return u.split()


def fam_size(s):
    f = parse_family(s)
    return 0 if f is None else len(f)


def table(caption, label, colspec, header, body, size=r'\footnotesize', sep='2pt',
          placement='tbp', star_note=None):
    out = [r'\begin{table}[%s]' % placement, r'\caption{%s}' % caption, r'\label{%s}' % label,
           r'\centering', r'\setlength{\tabcolsep}{%s}' % sep, size,
           r'\begin{tabular}{%s}' % colspec, r'\toprule', header + r'\\', r'\midrule']
    out += body
    out += [r'\bottomrule', r'\end{tabular}', r'\end{table}']
    return '\n'.join(out) + '\n'


def yesno(b):
    return 'yes' if b else 'no'


# ---- row definitions ------------------------------------------------------------------------

ANALYSER = [  # csv row, label, goal
    ('signed_cr', 'signed CR', 'rec.\\ agr.'),
    ('two_key', r'\quad two-key variant', 'rec.\\ agr.'),
    ('nspk', 'Needham--Schroeder', 'agr.'),
    ('nspk_channels', r'\quad with channels', 'agr.'),
    ('nsl', r"\quad Lowe's fix", 'agr.'),
]
CPSA = [
    ('pkinit-flawed', r'\textsc{pkinit} (flawed)', 'auth.'),
    ('pkinit-fix2', r'\quad adopted fix', 'auth.'),
    ('isoreject', r'ISO 9798-3 (flawed)', 'agr.'),
    ('isofix', r'\quad corrected', 'agr.'),
    ('blanchet', 'Blanchet', 'secr.\\ $d$'),
    ('blanchet-fixed', r'\quad fixed', 'secr.\\ $d$'),
    ('otway-rees', 'Otway--Rees', 'agr.'),
    ('otway-rees-neq', r'\quad with $A \neq B$', 'agr.'),
    ('yahalom', 'Yahalom', 'agr.'),
    ('denning-sacco', 'Denning--Sacco', 'agr.'),
    ('neuman-stubblebine', 'Neuman--Stubblebine', 'agr.'),
    ('kerberos-names', 'Kerberos (simplified)', 'init.\\ agr.'),
    ('kerberos-key', '\\quad agreement on $K$', 'agr.\\ $K$'),
]

# ---- protocol rows (a) ------------------------------------------------------------------------


def make_rows(d, out, nums):
    rows = read(os.path.join(d, 'rows.csv'))
    R = {(r['row'], r['witness_mode'], r['shrink']): r for r in rows}
    cpsa = {r['row']: r for r in read(os.path.join(d, 'cpsa_rows.csv'))}
    bound = read(os.path.join(d, 'bound.csv'))
    ch2 = [r for r in bound if r['row'] == 'nspk_channels' and r['instances_per_role'] == '2'
           and r['earlier_session'] == 'false'][0]

    body = []
    n_rows = n_agree = 0
    for key, label, goal in ANALYSER:
        r = R[(key, 'pruned', 'false')]
        agree_all = all(R[(key, m, s)]['brute_force_agrees'] == 'true'
                        for m in ('as_found', 'pruned', 'least') for s in ('false', 'true'))
        U = u_atoms_analyser(r['U'])
        ulines = []
        for i in range(0, len(U), 2):
            ulines.append(', '.join('$%s$' % atom_tex(a) for a in U[i:i + 2]))
        wl = fam_lines(r['W'])
        n = max(len(ulines), len(wl))
        ulines += [''] * (n - len(ulines))
        wl += [''] * (n - len(wl))
        for i in range(n):
            if i == 0:
                body.append('%s & A & %s & %d & %s & %s & %s & %s\\\\' % (
                    label, goal, len(U), ulines[0], wl[0], fam_size(r['H']), yesno(agree_all)))
            else:
                body.append(' & & & & %s & %s & & \\\\' % (ulines[i], wl[i]))
        n_rows += 1
        n_agree += agree_all
        if key == 'nspk_channels':
            wl = fam_lines(ch2['W'])
            for i, l in enumerate(wl):
                if i == 0:
                    body.append(r'\quad\quad two instances & A & agr. & 6 & & %s & %s & n/c\\' % (
                        l, fam_size(ch2['H'])))
                else:
                    body.append(' & & & & & %s & & \\\\' % l)
    for key, label, goal in CPSA:
        r = cpsa[key]
        U = u_atoms_cpsa(r['U'])
        ok = r['asfound_agrees'] == 'yes' and r['shrink_agrees'] == 'yes' and \
            r['asfound_H_eq_A'] == 'yes' and r['shrink_H_eq_A'] == 'yes'
        ulines = []
        for i in range(0, len(U), 2):
            ulines.append(', '.join('$%s$' % atom_tex(a) for a in U[i:i + 2]))
        W = r['W_exh']
        f = parse_family(W)
        if f and len(f) == 1 and len(f[0]) > 2:
            # one long set: split it over lines, two atoms per line
            xs = [atom_tex(a) for a in f[0]]
            wl = []
            for i in range(0, len(xs), 2):
                part = ', '.join(xs[i:i + 2])
                pre = r'\{' if i == 0 else ''
                post = r'\}' if i + 2 >= len(xs) else ','
                wl.append('$%s%s%s$' % (pre, part, post))
        else:
            wl = fam_lines(W)
        n = max(len(ulines), len(wl))
        ulines += [''] * (n - len(ulines))
        wl += [''] * (n - len(wl))
        for i in range(n):
            if i == 0:
                body.append('%s & C & %s & %s & %s & %s & %s & %s\\\\' % (
                    label, goal, r['n_U'], ulines[0], wl[0], r['n_A'], yesno(ok)))
            else:
                body.append(' & & & & %s & %s & & \\\\' % (ulines[i], wl[i]))
        n_rows += 1
        n_agree += ok
    cap = (r'Every protocol row: candidate assumptions $U$, the weakest trust $\weakest(\chi)$ returned by '
           r'Algorithm~\ref{alg:loop}, and the number of minimal attacks $|\attacks|$, over our analyser (A) or '
           r'CPSA (C). ``agrees' "''" r' means that in every witness mode (Table~\ref{tab:calls}) the '
           r'loop returned the minimal sufficient trusts found by evaluating all $2^{|U|}$ trusts '
           r'with the same oracle; n/c: not '
           r'checked. $k_{XS}$ is $X$'"'"r's long-term key shared with the server. Goals: (recent) '
           r'agreement of the responder with the initiator; the client'"'"r's authentication of the '
           r'server; secrecy of $d$; the initiator'"'"r's agreement on the names and the session key $K$ (Kerberos), or on $K$ alone (agreement on $K$). '
           r'$\mathsf{false}$ is the unrealisable answer (Remark~\ref{rem:unrealisable}). The '
           r'channel row is shown with one instance per role (the pool on which it was checked) '
           r'and with two (Section~\ref{sec:eval-bound}). The goals and $U$ of the CPSA rows are '
           r'in Appendix~\ref{app:protocols}.')
    hdr = r'protocol & & goal & $|U|$ & $U$ & $\weakest(\chi)$ & $|\attacks|$ & agrees'
    open(os.path.join(out, 'long_rows.tex'), 'w').write(
        table(cap, 'tab:results', 'l c l r l l r c', hdr, body, sep='2.5pt'))
    nums.update({'NRows': n_rows, 'NRowsAgree': n_agree, 'NAnalyserRows': len(ANALYSER),
                 'NCpsaRows': len(CPSA),
                 'MaxU': max([len(u_atoms_analyser(R[(k, 'pruned', 'false')]['U'])) for k, _, _ in ANALYSER]
                             + [int(cpsa[k]['n_U']) for k, _, _ in CPSA]),
                 'MinU': min([len(u_atoms_analyser(R[(k, 'pruned', 'false')]['U'])) for k, _, _ in ANALYSER]
                             + [int(cpsa[k]['n_U']) for k, _, _ in CPSA]),
                 'NFalse': sum(fam_size(R[(k, 'pruned', 'false')]['W']) == 0 for k, _, _ in ANALYSER)
                 + sum(cpsa[k]['n_W'] == '0' for k, _, _ in CPSA),
                 'NCpsaMonotone': sum(cpsa[k]['monotone'] == 'yes' for k, _, _ in CPSA),
                 'NCpsaPoints': sum(int(cpsa[k]['points']) for k, _, _ in CPSA)})
    return R, cpsa


# ---- calls per witness mode (a, continued) ----------------------------------------------------


def make_calls(d, out, nums, R, cpsa):
    body = []
    pruned_at = least_at = 0
    an_over = []
    for key, label, _ in ANALYSER:
        g = lambda m, s='false': R[(key, m, s)]
        r = g('pruned')
        N = int(r['H_plus_W'])
        nU = len(u_atoms_analyser(r['U']))
        body.append('%s & A & %d & %s & %s & %s & %s & -- & -- & %s & -- & --\\\\' % (
            label, N, g('as_found')['distinct_calls'], g('pruned')['distinct_calls'],
            g('least')['distinct_calls'], g('as_found', 'true')['distinct_calls'], num(2 ** nU)))
        pruned_at += int(g('pruned')['distinct_calls']) <= N
        least_at += int(g('least')['distinct_calls']) <= N
        if int(g('pruned')['distinct_calls']) > N:
            an_over.append(key)
    over = 0
    for key, label, _ in CPSA:
        r = cpsa[key]
        N = int(r['N'])
        over += int(r['asfound_distinct']) > N
        body.append('%s & C & %d & %s & -- & -- & %s & %s{+}%s & %s{+}%s & %s & %s & %s\\\\' % (
            label, N, r['asfound_distinct'], r['shrink_distinct'],
            r['asfound_goal_runs'], r['asfound_replay_runs'],
            r['shrink_goal_runs'], r['shrink_replay_runs'],
            num(int(r['points'])), r['b2_calls'], r['b3_calls']))
    cap = (r'Distinct oracle calls of Algorithm~\ref{alg:loop} per witness mode, against $N = |\attacks(\chi)| + '
           r'|\weakest(\chi)|$, the bound of Theorem~\ref{thm:cost} for witnesses with minimal stopping sets. As found: '
           r'the first attack the oracle reports (for CPSA, the failing shape with the smallest '
           r'clause); pruned: the analyser'"'"r's run pruned to a minimal run; least: a run whose '
           r'stopping set is least among all attacks the analyser reaches; shrink: as-found '
           r'witnesses minimalised by further calls (counted). CPSA runs are goal runs $+$ replay '
           r'runs that compute $\stops(x)$. B1 evaluates all $2^{|U|}$ trusts; B2 enumerates trusts by '
           r'size, skipping supersets of sufficient ones; B3 is the conjunct-dropping method '
           r'of~\cite{rowe}, which returns one minimal sufficient trust. B2 and B3 were run on the CPSA rows only.')
    hdr = (r'protocol & & $N$ & \multicolumn{4}{c}{calls of Algorithm~\ref{alg:loop}} & '
           r'\multicolumn{2}{c}{CPSA runs} & B1 & B2 & B3\\' '\n'
           r'\cmidrule(lr){4-7}\cmidrule(lr){8-9}' '\n'
           r' & & & as found & pruned & least & shrink & as found & shrink & & &')
    open(os.path.join(out, 'long_calls.tex'), 'w').write(
        table(cap, 'tab:calls', 'l c r r r r r r r r r r', hdr, body, sep='3pt'))
    nums.update({
        'SignedAsFound': R[('signed_cr', 'as_found', 'false')]['distinct_calls'],
        'SignedPruned': R[('signed_cr', 'pruned', 'false')]['distinct_calls'],
        'TwoKeyPruned': R[('two_key', 'pruned', 'false')]['distinct_calls'],
        'NAnalyserPrunedAtBound': pruned_at, 'NAnalyserLeastAtBound': least_at,
        'NCpsaOverBound': over,
        'NCpsaGoalRuns': sum(int(cpsa[k]['asfound_goal_runs']) for k, _, _ in CPSA),
        'NCpsaReplayRuns': sum(int(cpsa[k]['asfound_replay_runs']) for k, _, _ in CPSA),
        'NCpsaShrinkReplayRuns': sum(int(cpsa[k]['shrink_replay_runs']) for k, _, _ in CPSA),
        'NCpsaRejected': sum(int(cpsa[k]['asfound_rejected']) for k, _, _ in CPSA),
        'NCpsaRejectedRows': sum(int(cpsa[k]['asfound_rejected']) > 0 for k, _, _ in CPSA),
        'NCpsaIllFormed': sum(int(cpsa[k]['asfound_ill_formed']) + int(cpsa[k]['shrink_ill_formed'])
                              for k, _, _ in CPSA),
        'NShrinkAgree': sum(cpsa[k]['shrink_agrees'] == 'yes' for k, _, _ in CPSA),
        'NGreedyInW': sum(cpsa[k]['b3_in_W'] == 'yes' for k, _, _ in CPSA),
        'NLevelwiseAgree': sum(cpsa[k]['b2_found_eq_W'] == 'yes' for k, _, _ in CPSA),
        'NShrinkFewerReplays': sum(int(cpsa[k]['shrink_replay_runs']) < int(cpsa[k]['asfound_replay_runs'])
                                   for k, _, _ in CPSA),
        'NShrinkMoreCalls': sum(int(cpsa[k]['shrink_distinct']) > int(cpsa[k]['asfound_distinct'])
                                for k, _, _ in CPSA),
        'NLevelwiseFewerCalls': sum(int(cpsa[k]['b2_calls']) < int(cpsa[k]['asfound_goal_runs'])
                                    + int(cpsa[k]['asfound_replay_runs']) for k, _, _ in CPSA),
    })


# ---- CPSA timing (b) --------------------------------------------------------------------------

METHODS = [('weakest', 'Alg.~1'), ('weakest_shrink', 'shrink'), ('exhaustive_B1', 'B1'),
           ('levelwise_B2', 'B2'), ('greedy_B3', 'B3')]


def make_timing(d, out, nums):
    T = {(t['row'], t['method']): t for t in read(os.path.join(d, 'cpsa_timing_summary.csv'))}
    body = []
    for key, label, _ in CPSA:
        cells = []
        for m, _ in METHODS:
            t = T[(key, m)]
            cells.append('%.3f & (%.3f)' % (float(t['wall_median_s']), float(t['wall_iqr_s'])))
        shares = [round(100 * float(T[(key, m)]['cpsa_share_median'])) for m, _ in METHODS]
        rng = '%d' % min(shares) if min(shares) == max(shares) else '%d--%d' % (min(shares), max(shares))
        body.append('%s & %s & %s\\\\' % (label, ' & '.join(cells), rng))
    reps = sorted({T[k]['reps'] for k in T})
    cap = (r'Wall-clock time in seconds per CPSA row and method: median of %s repetitions after one '
           r'warm-up, with the interquartile range in parentheses. Methods as in '
           r'Table~\ref{tab:calls}; B3 returns one trust, not $\weakest(\chi)$. The last column '
           r'is the range over the methods of the median share of the wall time spent in CPSA.'
           % '/'.join(reps))
    hdr = ('protocol & ' + ' & '.join(r'\multicolumn{2}{c}{%s}' % n for _, n in METHODS)
           + r' & CPSA \%')
    open(os.path.join(out, 'long_cpsa_timing.tex'), 'w').write(
        table(cap, 'tab:timing', 'l' + ' r@{\\,}l' * 5 + ' r', hdr, body, sep='3pt'))
    med = lambda k, m: float(T[(k, m)]['wall_median_s'])
    shares = [float(t['cpsa_share_median']) for t in T.values()]
    nums.update({
        'CpsaShareMin': round(100 * min(shares)), 'CpsaShareMax': round(100 * max(shares)),
        'CpsaMaxAny': '%.1f' % max(float(t['wall_median_s']) for t in T.values()),
        'CpsaMaxIqr': '%.2f' % max(float(t['wall_iqr_s']) for t in T.values()),
        'CpsaReps': '/'.join(reps),
        'NLoopFasterThanExh': sum(med(k, 'weakest') < med(k, 'exhaustive_B1') for k, _, _ in CPSA),
        'NLevelwiseFasterThanLoop': sum(med(k, 'levelwise_B2') < med(k, 'weakest') for k, _, _ in CPSA),
        'NShrinkFasterThanLoop': sum(med(k, 'weakest_shrink') < med(k, 'weakest') for k, _, _ in CPSA),
        'NGreedyFastest': sum(min(METHODS, key=lambda mm: med(k, mm[0]))[0] == 'greedy_B3'
                              for k, _, _ in CPSA),
    })


# ---- channels (c) -----------------------------------------------------------------------------


def make_channels(d, out, nums):
    C = {r['row']: r for r in read(os.path.join(d, 'channels.csv'))}
    order = [('nspk', 'Needham--Schroeder', 'keys', 'no'),
             ('nspk_channels', '', 'keys, channels', 'no'),
             ('nspk_channels_hijack', '', 'keys, channels', 'yes'),
             ('nsl', "Lowe's fix", 'keys', 'no'),
             ('nsl_channels', '', 'keys, channels', 'no'),
             ('nsl_channels_hijack', '', 'keys, channels', 'yes')]
    body = []
    changed = 0
    for i, (key, label, u, hj) in enumerate(order):
        r = C[key]
        if i == 3:
            body.append(r'\midrule')
        w1 = fam_lines(r['W'])
        w2 = fam_lines(r['W_2_instances'])
        n = max(len(w1), len(w2))
        w1 += [''] * (n - len(w1))
        w2 += [''] * (n - len(w2))
        for j in range(n):
            if j == 0:
                body.append('%s & %s & %s & %s & %s & %s & %s & %s\\\\' % (
                    label, u, hj, w1[0], fam_size(r['H']), r['distinct_calls'], w2[0],
                    num(int(r['states_2_instances']))))
            else:
                body.append(' & & & %s & & & %s & \\\\' % (w1[j], w2[j]))
        changed += r['W_changed_at_2_instances'] == 'true'
    cap = (r'Channel assumptions on Needham--Schroeder and Lowe'"'"r's fix: $U$ holds the two '
           r'long-term keys and, in the channel rows, $\auth(c)$ and $\conf(c)$ for $c \in '
           r'\{A{\to}B, B{\to}A\}$. ``hijack' "''" r' adds the transition that re-ascribes a '
           r'message to another channel without learning it. One instance per role (least '
           r'witnesses; calls, $|\attacks|$ and agreement with evaluating every trust with the same oracle, as in '
           r'Table~\ref{tab:results}), and two instances per role with the states explored '
           r'by the reduced search.')
    hdr = (r'protocol & $U$ & hijack & $\weakest$, 1 instance & $|\attacks|$ & calls & '
           r'$\weakest$, 2 instances & states')
    open(os.path.join(out, 'long_channels.tex'), 'w').write(
        table(cap, 'tab:channels', 'l l c l r r l r', hdr, body, sep='3pt'))
    nums.update({'NChannelRows': len(order), 'NChannelChanged': changed,
                 'NChannelAgree': sum(C[k]['brute_force_agrees'] == 'true' for k, *_ in order)})


# ---- bound sensitivity (d) --------------------------------------------------------------------


def make_bound(d, out, nums):
    B = read(os.path.join(d, 'bound.csv'))
    LBL = {'signed_cr': 'signed CR', 'two_key': 'two-key variant', 'nspk': 'Needham--Schroeder',
           'nspk_channels': 'N--S with channels', 'nsl': "Lowe's fix"}
    body = []
    first = True
    for key, *_ in ANALYSER:
        for earlier in ('true', 'false'):
            rs = sorted([r for r in B if r['row'] == key and r['earlier_session'] == earlier],
                        key=lambda r: int(r['instances_per_role']))
            if not rs:
                continue
            if not first:
                body.append(r'\addlinespace[2pt]')
            first = False
            one = [r for r in rs if r['instances_per_role'] == '1'][0]
            for r in rs:
                inst = r['instances_per_role']
                lead = ('%s & %s' % (LBL[key], 'yes' if earlier == 'true' else 'no')) \
                    if inst == '1' else ' & '
                if r['status'] != 'ok':
                    body.append(r'%s & %s & \multicolumn{3}{l}{timeout} & %s\\' % (
                        lead, inst, tsec(float(r['time_s']))))
                    continue
                if inst != '1' and r['W'] == one['W']:
                    wl = ['same']
                else:
                    wl = fam_lines(r['W'])
                body.append('%s & %s & %s & %s & %s & %s\\\\' % (
                    lead, inst, wl[0], r['distinct_calls'], num(int(r['states_explored'])),
                    tsec(float(r['time_s']))))
                for l in wl[1:]:
                    body.append(' & & & %s & & & \\\\' % l)
    cap = (r'Sensitivity of $\weakest(\chi)$ to the analyser'"'"r's pool: instances per role, with '
           r'or without one earlier completed session whose transcript the adversary holds (pruned '
           r'witnesses, reduced search). ``same' "''" r' means equal to the one-instance answer with '
           r'the same session setting. States are summed over all calls of one run of '
           r'Algorithm~\ref{alg:loop}; time is the wall-clock time of that run in seconds, with a limit of '
           r'%s\,s.' % nums['BoundTimeout'])
    hdr = r'row & earlier & inst. & $\weakest(\chi)$ & calls & states & time (s)'
    open(os.path.join(out, 'long_bound.tex'), 'w').write(
        table(cap, 'tab:bound', 'l c c l r r r', hdr, body, sep='3pt'))


def bound_numbers(d, nums):
    B = read(os.path.join(d, 'bound.csv'))
    ok = [r for r in B if r['status'] == 'ok']
    to = [r for r in B if r['status'] != 'ok']
    nums['BoundTimeout'] = '%d' % round(min(float(r['time_s']) for r in to)) if to else '--'
    two = [r for r in ok if r['instances_per_role'] == '2']
    nums.update({
        'NBoundRuns': len(B), 'NBoundTimeouts': len(to),
        'BoundMaxStatesTwo': num(max(int(r['states_explored']) for r in two)),
        'BoundMaxTimeTwo': tsec(max(float(r['time_s']) for r in two)),
        'BoundMaxStatesOne': num(max(int(r['states_explored']) for r in ok if r['instances_per_role'] == '1')),
    })


# ---- scale (e) --------------------------------------------------------------------------------

NAMES = {
    'rand-m1': r'random, $m=n$', 'rand-m2': r'random, $m=2n$', 'rand-m4': r'random, $m=4n$',
    'pairs': 'disjoint pairs', 'dual': 'dual of pairs',
    'thr': r'all $\frac{n}{2}$-sets', 'thr-dual': r'all $(\frac{n}{2}{+}1)$-sets',
}


def scale_rows(counts, timing, fam):
    by = defaultdict(list)
    for r in counts:
        if r['family'] == fam:
            by[(int(r['n']), r['method'])].append(r)
    tim = defaultdict(list)
    for r in timing:
        if r['family'] == fam and r['wall_median']:
            tim[int(r['n'])].append(r)
    ns = sorted({n for n, _ in by})
    lines = []
    for n in ns:
        a = by[(n, 'alg1')]
        aok = [r for r in a if r['status'] == 'ok']
        seeds = len({r['seed'] for r in by[(n, 'b3')]} | {r['seed'] for r in a})
        if aok:
            H = [int(r['H']) for r in aok]
            W = [int(r['W']) for r in aok]
            Cl = [int(r['calls']) for r in aok]
            hcol = num(statistics.median(H))
            wcol = num(statistics.median(W)) if len(aok) == 1 else '%s (%s)' % (
                num(statistics.median(W)), num(max(W)))
            ccol = num(statistics.median(Cl))
            scol = '%d/%d' % (len(aok), len(a)) if len(a) != 1 else ('1/1')
        elif a:
            hcol = wcol = ccol = ''
            scol = '0/%d' % len(a)
        else:
            hcol = wcol = ccol = scol = ''
        trs = tim.get(n, [])
        if trs and aok:
            meds = [float(r['wall_median']) for r in trs]
            tm = statistics.median(meds)
            if len(trs) == 1:
                iqr = float(trs[0]['wall_iqr'])
                tcol = tsec_sci(tm)
            else:
                q1, q3 = quartiles(meds)
                iqr = q3 - q1
                tcol = tsec_sci(tm) + r'$^{*}$'
            icol = tsec_sci(iqr)
        else:
            tcol = icol = ''
        if a and not aok:
            hcol, wcol, ccol, tcol, icol = r'\multicolumn{5}{c}{timeout}', None, None, None, None

        def med_or(meth):
            rs = by[(n, meth)]
            if not rs:
                return ''
            ok = [r for r in rs if r['status'] == 'ok']
            if not ok:
                return 't/o'
            s = num(statistics.median(int(r['calls']) for r in ok))
            return s if len(ok) == len(rs) else s + r'$^{\dagger}$'
        pcol = med_or('padded')
        shcol = med_or('padded_shrink')
        b1 = by[(n, 'b1')]
        if not b1:
            b1col = ''
        elif all(r['status'] == 'ok' for r in b1):
            b1col = num(2 ** n)
        else:
            b1col = 't/o'
        b2 = by[(n, 'b2')]
        if not b2:
            b2col = ''
        elif any(r['status'] != 'ok' for r in b2):
            b2col = 't/o'
        elif any(r['complete'] == '0' for r in b2):
            b2col = r'$>2^{21}$'
        else:
            b2col = num(statistics.median(int(r['calls']) for r in b2))
        b3 = [r for r in by[(n, 'b3')] if r['status'] == 'ok']
        b3c = num(statistics.median(int(r['calls']) for r in b3)) if b3 else ''
        b3w = '%d/%d' % (sum(r['in_W'] == '1' for r in b3), len(b3)) if b3 else ''
        cells = [str(n), scol]
        if wcol is None:
            cells += [hcol]
        else:
            cells += [hcol, wcol, ccol, tcol, icol]
        cells += [pcol, shcol, b1col, b2col, b3c, b3w]
        lines.append(' & '.join(cells) + r'\\')
    return lines


def make_scale(d, out, nums):
    counts = read(os.path.join(d, 'scale_counts.csv'))
    timing = read(os.path.join(d, 'scale_timing.csv'))
    hdr = (r'$n$ & seeds & $|\attacks|$ & $|\weakest|$ & calls & time (s) & IQR & padded & shrink '
           r'& B1 & B2 & \multicolumn{2}{c}{B3}\\' '\n'
           r'\cmidrule(lr){12-13}' '\n'
           r' & & & & & & & & & & & calls & in $\weakest$')
    ncol = 13
    capfmt = (r'Algorithm~\ref{alg:loop} on instances from the reduction in the proof of Theorem~\ref{thm:cost} (Fig.~\ref{fig:gadget}), %s, one row '
              r'per $n$. Seeds: runs of Algorithm~\ref{alg:loop} completed within %s\,s over runs started (a series '
              r'stops at the first $n$ with a timeout; empty cells were not run). $|\attacks|$, '
              r'$|\weakest|$ (maximum in parentheses when there are several seeds) and calls are '
              r'medians over completed seeds; calls are distinct oracle calls with minimal witnesses. '
              r'Time is the median wall-clock time of Algorithm~\ref{alg:loop} for seed 0 over its repetitions, '
              r'with their interquartile range; $^{*}$ marks rows timed on every seed, where time and '
              r'IQR are over the per-seed medians. Padded: witnesses padded with two atoms outside the '
              r'trust; shrink: padded witnesses minimalised; $^{\dagger}$ median over the seeds that '
              r'completed. B1, B2, B3 as in Table~\ref{tab:calls}; B2 stops after $2^{21}$ calls; '
              r'B3 counts the seeds whose single answer is in $\weakest$.')
    TO = nums['ScaleTimeout']
    groups = [('long_scale_random.tex', 'tab:scale', 'random families',
               ['rand-m1', 'rand-m2', 'rand-m4']),
              ('long_scale_struct.tex', 'tab:scale-struct', 'structured families',
               ['pairs', 'dual', 'thr', 'thr-dual'])]
    for fn, label, what, fams in groups:
        body = []
        for i, f in enumerate(fams):
            if i:
                body.append(r'\midrule')
            body.append(r'\multicolumn{%d}{l}{%s}\\' % (ncol, NAMES[f]))
            body += scale_rows(counts, timing, f)
        cap = capfmt % (what, TO)
        if fams[0] == 'pairs':
            cap = (cap + r' Disjoint pairs: $n/2$ edges $\{2i, 2i{+}1\}$, so $|\weakest| = 2^{n/2}$; '
                   r'dual of pairs: its blocker, so $|\attacks| = 2^{n/2}$; threshold families: all '
                   r'subsets of size $n/2$, and of size $n/2+1$, of $n$ candidate assumptions. One instance per $n$.')
        else:
            cap = (cap + r' Each random instance draws $m$ edges of size one to three over $n$ '
                   r'candidate assumptions and minimalises them.')
        open(os.path.join(out, fn), 'w').write(
            table(cap, label, 'r r r r r r r r r r r r r', hdr, body, size=r'\scriptsize',
                  sep='2.6pt', placement='p'))

    alg = [r for r in counts if r['method'] == 'alg1']
    aok = [r for r in alg if r['status'] == 'ok']
    pad = [r for r in counts if r['method'] == 'padded' and r['status'] == 'ok']
    psh = [r for r in counts if r['method'] == 'padded_shrink' and r['status'] == 'ok']
    b3 = [r for r in counts if r['method'] == 'b3' and r['status'] == 'ok']
    b2 = [r for r in counts if r['method'] == 'b2' and r['status'] == 'ok']
    dg = defaultdict(dict)
    for r in counts:
        if r['status'] == 'ok' and r['w_digest']:
            dg[(r['family'], r['n'], r['m'], r['seed'])][r['method']] = r['w_digest']
    mism = sum(len(set(v.values())) > 1 for v in dg.values())
    tm = [float(r['wall_median']) for r in timing if r['wall_median']]
    blk = [(float(r['blocker_median']), float(r['oracle_median'])) for r in timing
           if r['wall_median'] and float(r['wall_median']) >= 1]
    nums.update({
        'NScaleRuns': num(len(counts)),
        'NScaleTimeouts': sum(r['status'] != 'ok' for r in counts),
        'NAlgRuns': len(aok), 'NAlgTimeouts': len(alg) - len(aok),
        'NAlgAtBound': sum(int(r['calls']) == int(r['H']) + int(r['W']) for r in aok),
        'NAlgHRecovered': sum(r['h_recovered'] == '1' for r in aok),
        'NPaddedRuns': len(pad),
        'NPaddedOverBound': sum(int(r['calls']) > int(r['H']) + int(r['W']) for r in pad),
        'NShrinkRuns': len(psh),
        'NShrinkWithin': sum(r['within_bound'] == '1' for r in psh),
        'NBthreeRuns': num(len(b3)), 'NBthreeInW': num(sum(r['in_W'] == '1' for r in b3)),
        'NBtwoBudget': sum(r['complete'] == '0' for r in b2),
        'NDigestInstances': num(len(dg)), 'NDigestMismatch': mism,
        'MaxN': max(int(r['n']) for r in aok),
        'MaxW': num(max(int(r['W']) for r in aok)),
        'MaxH': num(max(int(r['H']) for r in aok)),
        'ScaleMaxTime': tsec(max(tm)),
        'NScaleTimed': len(tm),
        'NScaleSlowRuns': len(blk),
        'NScaleBlockerDominates': sum(b > o for b, o in blk),
    })


def scale_numbers_manifest(d, nums):
    txt = open(os.path.join(d, 'manifest_scale.txt')).read()
    m = re.search(r'timeout (\d+) s per run', txt)
    nums['ScaleTimeout'] = m.group(1)
    m = re.search(r'budget (\d+)', txt)
    nums['BtwoBudget'] = num(int(m.group(1)))
    m = re.search(r'heap cap (\d+) MB', txt)
    nums['ScaleHeapCap'] = num(int(m.group(1)))
    m = re.search(r'seeds: ([\d ]+)\(', txt)
    nums['NSeeds'] = len(m.group(1).split())
    m = re.search(r'counts phase: (\d+) parallel workers', txt)
    nums['ScaleWorkers'] = m.group(1)


# ---- gadget (f) -------------------------------------------------------------------------------


def make_gadget(d, out, nums):
    G = read(os.path.join(d, 'gadget_check.csv'))
    body = []
    for r in G:
        edges = ', '.join(r'\{%s\}' % ','.join(e.split('.')) for e in r['edges'].split())
        body.append(r'%s & %s & $%s$ & %s & %s & %s/%s & %s & %s & %s\\' % (
            r['id'], r['n'], edges, r['H'], r['W'], r['agree'], r['trusts'],
            yesno(r['loop_w_equal'] == '1' and r['loop_h_equal'] == '1'), r['gadget_distinct'],
            tsec(float(r['time']))))
    cap = (r'Gadget check: for each hypergraph (edges over candidate assumptions $0, \dots, n-1$) the protocol '
           r'of the reduction in the proof of Theorem~\ref{thm:cost}, decided by exhaustive bounded '
           r'Dolev--Yao search, against the hypergraph oracle (``does $T$ meet every edge' "''" r'). '
           r'Agree: trusts on which both give the same verdict and, on failure, the gadget'"'"r's '
           r'stopping set is an edge disjoint from $T$. Loop: Algorithm~\ref{alg:loop} over the gadget oracle '
           r'returns the blocker of the edges and recovers the edges as $\attacks$; calls are its '
           r'distinct calls. Time in seconds for the whole check.')
    hdr = r'instance & $n$ & edges & $|\attacks|$ & $|\weakest|$ & agree & loop & calls & time (s)'
    open(os.path.join(out, 'long_gadget.tex'), 'w').write(
        table(cap, 'tab:gadget', 'l r l r r r c r r', hdr, body, size=r'\scriptsize',
              sep='3pt'))
    nums.update({
        'NGadget': len(G), 'GadgetMaxN': max(int(r['n']) for r in G),
        'NGadgetAgree': sum(r['status'] == 'ok' and r['agree'] == r['trusts']
                            and r['loop_w_equal'] == '1' and r['loop_h_equal'] == '1' for r in G),
        'NGadgetTrusts': num(sum(int(r['trusts']) for r in G)),
        'GadgetMaxTime': tsec(max(float(r['time']) for r in G)),
    })


# ---- appendix data per CPSA row ---------------------------------------------------------------


def parse_template(path):
    txt = open(path).read()
    head = {'U': [], 'note': []}
    for line in txt.splitlines():
        m = re.match(r';; @(\w+) (.*)', line)
        if not m:
            continue
        k, v = m.groups()
        if k == 'U':
            a, fact = v.split(' ', 1)
            head['U'].append((a, fact.strip()))
        elif k == 'note':
            head['note'].append(v.strip())
        else:
            head[k] = v.strip()
    i = txt.index('(defgoal')
    goal = txt[i:].rstrip() + '\n'
    proto = txt[:i]
    # role-level declarations
    decls = []
    for m in re.finditer(r'\(defrole\s+([\w-]+)', proto):
        role = m.group(1)
        j = m.end()
        nxt = proto.find('(defrole', j)
        seg = proto[j:nxt if nxt >= 0 else len(proto)]
        for dm in re.finditer(r'\((uniq-orig|non-orig|uniq-gen|pen-non-orig)\s+([^()]*(?:\([^()]*\)[^()]*)*)\)', seg):
            decls.append((role, dm.group(1), ' '.join(dm.group(2).split())))
    rules = re.findall(r'\(defrule\s+([\w-]+)', proto)
    return head, goal, decls, rules


def tt(s):
    return r'\texttt{%s}' % s.replace('_', r'\_').replace('#', r'\#')


def make_appendix(out, nums):
    pdir = os.path.join(ROOT, 'cpsa', 'protocols')
    for key, label, _ in CPSA:
        head, goal, decls, rules = parse_template(os.path.join(pdir, key + '.scm'))
        open(os.path.join(out, 'long_goal_%s.scm' % key), 'w').write(goal)
        lines = [r'\par\smallskip\noindent\begin{tabular}{@{}l p{0.8\textwidth}@{}}']
        lines.append(r'file & %s\\' % tt('cpsa/protocols/%s.scm' % key))
        ulines = ', '.join(r'$%s$ = %s' % (atom_tex(a), tt(f)) for a, f in head['U'])
        lines.append(r'$U$ & %s\\' % ulines)
        if decls:
            ds = '; '.join(r'%s in %s' % (tt('(%s %s)' % (k, v)), tt(role)) for role, k, v in decls)
            lines.append(r'in $\sigma$ & %s\\' % ds)
        if rules:
            lines.append(r'rules & %s\\' % ', '.join(tt(r) for r in rules))
        lines.append(r'\end{tabular}')
        lines.append(r'\lstinputlisting[language={},aboveskip=4pt]{tables/long_goal_%s.scm}' % key)
        open(os.path.join(out, 'long_app_%s.tex' % key), 'w').write('\n'.join(lines) + '\n')


# ---- implementation and environment numbers ---------------------------------------------------


def env_numbers(d, nums):
    man = open(os.path.join(d, 'manifest.txt')).read()
    g = lambda k: re.search(r'^%s: (.*)$' % k, man, re.M).group(1).strip()
    nums['Machine'] = g('machine')
    nums['OS'] = g('os')
    nums['OcamlVersion'] = re.search(r'([\d.]+)$', g('ocaml')).group(1)
    nums['DuneVersion'] = g('dune')
    nums['CpsaVersion'] = re.search(r'([\d.]+)', g('cpsa')).group(1)
    nums['SourcesSha'] = g('sources sha256')[:12]
    nums['RunStart'] = g('started')
    nums['RunEnd'] = g('finished')
    cm = open(os.path.join(d, 'manifest_cpsa.txt')).read()
    m = re.search(r'step limit (\d+), strand bound (\d+)', cm)
    nums['CpsaStepLimit'], nums['CpsaStrandBound'] = m.group(1), m.group(2)
    m = re.search(r'timeout per CPSA run: (\d+) s', cm)
    nums['CpsaTimeout'] = m.group(1)
    # load averages (1 min) logged at the start and end of each step
    log = open(os.path.join(d, 'run_all.log')).read()
    loads = {}
    for m in re.finditer(r'== (\w+) +(start|end) .* load: ([\d.]+) ([\d.]+) ([\d.]+)', log):
        loads.setdefault(m.group(1), []).append(float(m.group(3)))
    timed = ['rows', 'channels', 'scale_timing', 'bound']   # cpsa: see manifest_cpsa.txt
    vals = [v for k in timed for v in loads.get(k, [])]
    nums['LoadMin'] = '%.1f' % min(vals)
    nums['LoadMax'] = '%.1f' % max(vals)
    # the CPSA step was rerun alone after the review (manifest_cpsa.txt), so its load and
    # times come from that manifest, not from run_all.log
    cl = [float(x) for x in re.findall(r'load at (?:start|end) .*?load averages: ([\d.]+)', cm)]
    nums['CpsaLoadMin'] = '%.1f' % min(cl)
    nums['CpsaLoadMax'] = '%.1f' % max(cl)
    nums['CpsaRunStart'] = re.search(r'^start: (.*)$', cm, re.M).group(1)
    nums['CpsaRunEnd'] = re.search(r'^end: (.*)$', cm, re.M).group(1)
    # selection rule parameters, from the protocol manifest
    man = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'cpsa', 'protocols', 'MANIFEST.md')).read()
    nums['RowCap'] = re.search(r'\*\*Cap\.\*\* (\d+) rows', man).group(1)
    nums['SelectTimeout'] = re.search(r'within (\d+) s per', man).group(1)
    # first n at which a padded-witness run on a random family timed out
    sc = list(csv.DictReader(open(os.path.join(d, 'scale_counts.csv'))))
    pto = [int(r['n']) for r in sc if r['method'] == 'padded' and r['status'] != 'ok'
           and r['family'].startswith('rand')]
    nums['PaddedTimeoutN'] = min(pto) if pto else '--'
    nums['NSteps'] = len(loads)
    # source size
    lib = os.path.join(ROOT, 'lib')
    nums['LibLines'] = num(sum(sum(1 for _ in open(os.path.join(lib, f)))
                               for f in os.listdir(lib) if f.endswith('.ml')))
    # tests and differential checks
    tests = open(os.path.join(d, 'tests.stdout')).read()
    nums['NTestsPassed'] = num(sum(int(x) for x in re.findall(r'(\d+) passed', tests)))
    nums['NTestsFailed'] = sum(int(x) for x in re.findall(r'(\d+) failed', tests))
    dc = open(os.path.join(d, 'diff_core.stdout')).read()
    nums['NDiffCore'] = re.search(r'(\d+) cases', dc).group(1)
    nums['NDiffCoreMismatch'] = re.search(r'(\d+) mismatches', dc).group(1)
    db = open(os.path.join(d, 'diff_bounded.stdout')).read()
    nums['NDiffBoundedLines'] = re.search(r'(\d+) lines identical', db).group(1)
    dcp = open(os.path.join(d, 'diff_cpsa.stdout')).read()
    nums['NDiffCpsaRows'] = len(re.findall(r': agree', dcp))
    nums['NDiffCpsaFields'] = re.search(r'agree \((\d+) fields\)', dcp).group(1)


# ---- main -------------------------------------------------------------------------------------


def main(d, out):
    os.makedirs(out, exist_ok=True)
    nums = {}
    env_numbers(d, nums)
    scale_numbers_manifest(d, nums)
    bound_numbers(d, nums)
    R, cpsa = make_rows(d, out, nums)
    make_calls(d, out, nums, R, cpsa)
    make_timing(d, out, nums)
    make_channels(d, out, nums)
    make_bound(d, out, nums)
    make_scale(d, out, nums)
    make_gadget(d, out, nums)
    make_appendix(out, nums)
    with open(os.path.join(out, 'long_numbers.tex'), 'w') as f:
        f.write('%% generated by scripts/make_tables_long.py from %s\n'
                % os.path.relpath(d, ROOT))
        for k in sorted(nums):
            assert re.fullmatch(r'[A-Za-z]+', k), k
            f.write('\\newcommand{\\numL%s}{%s}\n' % (k, nums[k]))
    print('wrote %d macros and the long_* tables to %s' % (len(nums), out))


if __name__ == '__main__':
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'results', 'final')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, 'tables')
    main(d, os.path.normpath(out))
