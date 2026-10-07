#!/usr/bin/env python3
"""Generate the protocol tables of the paper from the experiment CSVs.

    python3 scripts/make_tables.py [RESULTS_DIR]     (default: results/final)

Reads rows.csv, bound.csv (analyser rows), cpsa_rows.csv and cpsa_timing_summary.csv
(CPSA rows). Writes RESULTS_DIR/tab_results.tex (Table tab:results),
RESULTS_DIR/tab_bound.tex (Table tab:bound) and RESULTS_DIR/numbers.tex (macros for
numbers quoted in the text). No number in these tables is typed by hand.
"""

import csv
import os
import re
import sys

# ---- atom names -> LaTeX ---------------------------------------------------------------

NONCE = {'n': 'N', 'na': 'n_A', 'nb': 'n_B', 'nc': 'n_C', 'm': 'M', 'k': 'K', 'ta': 't_A',
         'tb': 't_B', 'ra': 'r_A', 'rb': 'r_B', 't': 't', 'tp': "t'", 's': 's', 'd': 'd'}
KEY = {'privk_a': 'sk_A', 'privk_b': 'sk_B', 'privk_ks': 'sk_{KS}', 'as': 'sk(S)',
       'c': 'sk(C)', 'ltk_ac': 'k_{AS}', 'ltk_bc': 'k_{BS}', 'ltk_as': 'k_{AS}',
       'ltk_bs': 'k_{BS}', 'ltk_aks': 'k_{AS}', 'ltk_bks': 'k_{BS}'}


def atom_tex(a):
    a = a.strip()
    m = re.fullmatch(r'Non\((\w+)\)', a)
    if m:
        k = m.group(1)
        k = {'sk_A': 'sk_A', 'sk_B': 'sk_B', 'sk_C': 'sk_C', 'k1': 'k_1', 'k2': 'k_2', 'sk_A2': "sk'_A"}.get(k, k)
        return r'\Non(%s)' % k
    m = re.fullmatch(r'Unq\((\w+)\)', a)
    if m:
        return r'\Unq(%s)' % m.group(1)
    m = re.fullmatch(r'(auth|conf)\((\w)->(\w)\)', a)
    if m:
        return r'\%s(%s{\to}%s)' % m.groups()
    m = re.fullmatch(r'non_(\w+)', a)
    if m:
        return r'\Non(%s)' % KEY[m.group(1)]
    m = re.fullmatch(r'uniq_(\w+)', a)
    if m:
        return r'\Unq(%s)' % NONCE[m.group(1)]
    raise ValueError('unknown atom ' + a)


def parse_family(s):
    """'{a, b}; {c}' or '{a b} {c}' or '[]' or 'false' -> list of lists of atoms, or None
    for false."""
    s = s.strip()
    if s in ('false', '[]', ''):
        return None
    out = []
    for grp in re.findall(r'\{([^{}]*)\}', s):
        atoms = [x for x in re.split(r'[,\s]+', grp) if x]
        out.append(atoms)
    return out


def family_tex(fam, per_line=1, split=3):
    if fam is None:
        return [r'$\mathsf{false}$']
    sets = []
    for t in fam:
        xs = [atom_tex(a) for a in t]
        if len(xs) > split:   # long set: break after the second atom
            sets.append('$\\{%s,$' % ', '.join(xs[:2]))
            sets.append('$%s\\}$' % ', '.join(xs[2:]))
            per_line = 1
        else:
            sets.append('$\\{%s\\}$' % ', '.join(xs))
    lines, cur = [], []
    for x in sets:
        cur.append(x)
        if len(cur) == per_line:
            lines.append(', '.join(cur)); cur = []
    if cur:
        lines.append(', '.join(cur))
    return [l + (',' if i < len(lines) - 1 and not l.endswith(',$') else '')
            for i, l in enumerate(lines)]


def fam_size(s):
    f = parse_family(s)
    return 0 if f is None else len(f)


# ---- rows ------------------------------------------------------------------------------

ANALYSER = [  # (csv row, label, goal)
    ('signed_cr', r'signed CR (Sec.~\ref{sec:example})', 'rec.\\ agr.'),
    ('two_key', r'\quad two-key variant', 'rec.\\ agr.'),
    ('nspk', 'Needham--Schroeder', 'agr.'),
    ('nspk_channels', r'\quad with channels$^{\dagger}$', 'agr.'),
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


def read(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def main(d):
    rows = {r['row']: r for r in read(os.path.join(d, 'rows.csv'))
            if r['witness_mode'] == 'pruned' and r['shrink'] == 'false'}
    bound = read(os.path.join(d, 'bound.csv'))
    cpsa = {r['row']: r for r in read(os.path.join(d, 'cpsa_rows.csv'))}
    timing = read(os.path.join(d, 'cpsa_timing_summary.csv'))

    # channel row: report the two-instance pool (bound.csv), note the one-instance answer
    ch2 = [r for r in bound if r['row'] == 'nspk_channels' and r['instances_per_role'] == '2'
           and r['earlier_session'] == 'false'][0]

    body, n_ok, n_rows = [], 0, 0
    for key, label, goal in ANALYSER:
        r = rows[key]
        W, H, calls = r['W'], r['H'], r['distinct_calls']
        if key == 'nspk_channels':
            W, H, calls = ch2['W'], ch2['H'], ch2['distinct_calls']
        n_u = len(parse_family('{' + r['U'].strip('{}') + '}')[0])
        lines = family_tex(parse_family(W))
        body.append((label, 'A', goal, str(n_u), lines, str(fam_size(H)), calls, '--'))
        n_rows += 1; n_ok += r['brute_force_agrees'] == 'true'
    for key, label, goal in CPSA:
        r = cpsa[key]
        lines = family_tex(parse_family(r['W_exh']))
        if key == 'blanchet-fixed':
            lines = family_tex(parse_family(r['W_exh']), per_line=1)
        body.append((label, 'C', goal, r['n_U'], lines, r['n_A'], r['asfound_distinct'],
                     r['asfound_replay_runs']))
        n_rows += 1; n_ok += r['asfound_agrees'] == 'yes'

    out = []
    out.append(r'''\begin{table}[t]
\caption{Weakest trust recovered by Algorithm~1 with no assumption chosen by hand, over
our analyser (A) or CPSA (C), with $\weakest(\chi)$ equal to the minimal sufficient trusts
found by evaluating all $2^{|U|}$ trusts (for the channel row, at one instance per role). $|\attacks|$ is the number
of minimal attacks; calls are distinct verifier calls and repl.\ the extra CPSA runs
that compute $\stops(x)$ (Section~\ref{sec:computing}). $k_{XS}$ is $X$'s long-term key
shared with the server. Goals: (recent) agreement of the responder with the
initiator; the client's authentication of the server; secrecy of $d$; the
initiator's agreement on the session key $K$. $\mathsf{false}$ is the unrealisable answer
(Remark~\ref{rem:unrealisable}). $^{\dagger}$Two instances per role; with one,
$\{\auth(A{\to}B)\}$, $\{\conf(B{\to}A)\}$ (Section~\ref{sec:eval}).}
\label{tab:results}
\centering
\setlength{\tabcolsep}{1.6pt}
\footnotesize
\begin{tabular}{lcl r l r r r}
\toprule
protocol & & goal & $|U|$ & $\weakest(\chi)$ & $|\attacks|$ & calls & repl.\\
\midrule''')
    for (label, o, goal, nu, lines, na, calls, rep) in body:
        out.append('%s & %s & %s & %s & %s & %s & %s & %s\\\\' % (label, o, goal, nu, lines[0], na, calls, rep))
        for l in lines[1:]:
            out.append(' & & & & \\quad %s & & & \\\\' % l)
    out.append(r'''\bottomrule
\end{tabular}
\end{table}''')
    open(os.path.join(d, 'tab_results.tex'), 'w').write('\n'.join(out) + '\n')

    # ---- bound sensitivity table -------------------------------------------------------
    LBL = {'signed_cr': 'signed CR', 'two_key': 'two-key variant', 'nspk': 'Needham--Schroeder',
           'nspk_channels': 'N--S with channels', 'nsl': "Lowe's fix"}
    bt = [r'''\begin{table}[t]
\caption{Sensitivity of $\weakest(\chi)$ to the analyser's pool: instances per role,
with or without one earlier completed session. ``same'' means equal to the
one-instance answer with the same session setting; ``t/o'' a run over 600\,s.}
\label{tab:bound}
\centering
\setlength{\tabcolsep}{2pt}
\footnotesize
\begin{tabular}{l c p{2.9cm} p{3.3cm} c}
\toprule
row & earlier & 1 instance & 2 instances & 3\\
\midrule''']
    for key in ['signed_cr', 'two_key', 'nspk', 'nspk_channels', 'nsl']:
        for earlier in ['true', 'false']:
            rs = {r['instances_per_role']: r for r in bound
                  if r['row'] == key and r['earlier_session'] == earlier}
            if not rs:
                continue
            one = rs['1']
            def cell(k):
                r = rs.get(k)
                if r is None:
                    return '--'
                if r['status'] != 'ok':
                    return 't/o'
                if r['W'] == one['W']:
                    return 'same'
                return ' '.join(family_tex(parse_family(r['W']), per_line=9))
            first = ' '.join(family_tex(parse_family(one['W']), per_line=9))
            bt.append('%s & %s & %s & %s & %s\\\\' % (LBL[key], 'yes' if earlier == 'true' else 'no',
                                                     first, cell('2'), cell('3')))
    bt.append(r'''\bottomrule
\end{tabular}
\end{table}''')
    open(os.path.join(d, 'tab_bound.tex'), 'w').write('\n'.join(bt) + '\n')

    # ---- composition table (E7) ---------------------------------------------------------
    comp = read(os.path.join(d, 'compose.csv'))
    VN = {'tagged': 'tagged, shared $sk_A$', 'untagged': 'untagged, shared $sk_A$',
          'separate_keys': 'separate keys'}
    ct = [r'''\begin{table}[t]
\caption{Composition (Theorem~\ref{thm:composition}) of the signed challenge-response
($\chi_1$) with an attestation service ($\chi_2$). Last column: minimal attacks of the
composition that contain no component's minimal attack.}
\label{tab:composition}
\centering
\setlength{\tabcolsep}{3pt}
\footnotesize
\begin{tabular}{p{2.0cm} p{3.1cm} p{3.1cm} p{2.6cm}}
\toprule
pair & join of components & composition & cross-protocol\\
\midrule''']
    for r in comp:
        cross = []
        for g, k in (('\\chi_1', 'cross_protocol_chi1'), ('\\chi_2', 'cross_protocol_chi2')):
            v = r[k]
            if v != 'none':
                f = parse_family(v)
                cross.append(('$\\emptyset$' if f is None or f == [[]] else ' '.join(family_tex(f)))
                             + ' on $%s$' % g)
        ct.append('%s & %s & %s & %s\\\\' % (
            VN[r['variant']], ' '.join(family_tex(parse_family(r['join']), split=2)),
            ' '.join(family_tex(parse_family(r['W_comp']), split=2)), ', '.join(cross) or 'none'))
    ct.append(r'''\bottomrule
\end{tabular}
\end{table}''')
    open(os.path.join(d, 'tab_composition.tex'), 'w').write('\n'.join(ct) + '\n')

    # ---- numbers quoted in the text ----------------------------------------------------
    def med(rowname, method):
        for t in timing:
            if t['row'] == rowname and t['method'] == method:
                return float(t['wall_median_s'])
        return None
    shares = [float(t['cpsa_share_median']) for t in timing if t['cpsa_share_median']]
    over = sum(1 for k, _, _ in CPSA if int(cpsa[k]['asfound_distinct']) > int(cpsa[k]['N']))
    b3_in = sum(cpsa[k]['b3_in_W'] == 'yes' for k, _, _ in CPSA)
    sh_ok = sum(cpsa[k]['shrink_agrees'] == 'yes' for k, _, _ in CPSA)
    FAMILY = {'signed_cr': 'cr', 'two_key': 'cr', 'nspk': 'ns', 'nspk_channels': 'ns', 'nsl': 'ns',
              'pkinit-flawed': 'pkinit', 'pkinit-fix2': 'pkinit', 'isoreject': 'iso', 'isofix': 'iso',
              'blanchet': 'blanchet', 'blanchet-fixed': 'blanchet', 'otway-rees': 'or',
              'otway-rees-neq': 'or', 'yahalom': 'yahalom', 'denning-sacco': 'ds',
              'neuman-stubblebine': 'ns2', 'kerberos-key': 'kerberos', 'kerberos-names': 'kerberos'}
    rowkeys = [k for k, _, _ in ANALYSER] + [k for k, _, _ in CPSA]
    words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
             'ten', 'eleven', 'twelve']
    nprot = len({FAMILY[k] for k in rowkeys})
    nums = {
        'NProtocols': words[nprot] if nprot < len(words) else nprot,
        'NGreedyInW': b3_in, 'NShrinkAgree': sh_ok,
        'NRows': n_rows, 'NRowsAgree': n_ok, 'NCpsaRows': len(CPSA),
        'NCpsaOverBound': over,
        'CpsaShareMin': '%d' % round(100 * min(shares)),
        'CpsaShareMax': '%d' % round(100 * max(shares)),
        'CpsaMaxWeakest': '%.1f' % max(med(k, 'weakest') for k, _, _ in CPSA),
    }
    loop_faster = sum(med(k, 'weakest') < med(k, 'exhaustive_B1') for k, _, _ in CPSA)
    lw_faster = sum(med(k, 'levelwise_B2') < med(k, 'weakest') for k, _, _ in CPSA)
    nums.update({'NLoopFasterThanExh': loop_faster, 'NLevelwiseFasterThanLoop': lw_faster,
                 'CpsaMaxAny': '%.1f' % max(float(t['wall_median_s']) for t in timing)})
    sc = read(os.path.join(d, 'scale_counts.csv'))
    alg = [r for r in sc if r['method'] == 'alg1' and r['status'] == 'ok']
    gad = read(os.path.join(d, 'gadget_check.csv'))
    nums.update({
        'NScaleRuns': len(sc),
        'NScaleTimeouts': sum(r['status'] != 'ok' for r in sc),
        'NAlgRuns': len(alg),
        'NAlgAtBound': sum(r['equals_bound'] == '1' for r in alg),
        'MaxN': max(int(r['n']) for r in alg),
        'NGadget': len(gad),
        'GadgetMaxN': max(int(r['n']) for r in gad),
        'NGadgetAgree': sum(r['status'] == 'ok' and r['agree'] == r['trusts'] and r['loop_w_equal'] == '1' for r in gad),
    })
    with open(os.path.join(d, 'numbers.tex'), 'w') as f:
        for k, v in nums.items():
            f.write('\\newcommand{\\num%s}{%s}\n' % (k, v))
    print('rows: %d, agree with exhaustive: %d; CPSA rows over the bound: %d' % (n_rows, n_ok, over))
    print('wrote tab_results.tex, tab_bound.tex, numbers.tex in', d)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'results/final')
