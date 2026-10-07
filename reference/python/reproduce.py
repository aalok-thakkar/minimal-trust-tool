"""Reproduce the analyser rows of Table 2: python3 reproduce.py [--ablation]

For each row: run Algorithm 1 (cegis.weakest, memoised) over the bounded analyser and print
W(chi), the recovered minimal attacks H, distinct oracle calls, the calls the unmemoised
loop would make, and wall-clock time.

--ablation also reruns the two challenge-response rows with the DFS witness run as found
(not pruned to a minimal run), with and without witness shrinking (cegis.shrink_witness),
to show the effect of non-minimal witnesses on the call count.
"""

import sys
from time import perf_counter

import analyzer
import cr
from cegis import weakest

skA, skB = ('Non', 'sk_A'), ('Non', 'sk_B')


def nspk_oracle(nsl):
    def oracle(tau):
        r = analyzer.achieve(nsl, set(tau))
        return None if r is None else r[1]
    return oracle


# (row label, oracle, U, Table 2's W(chi), Table 2's / Section 9's call count or None)
ROWS = [
    ('signed CR', cr.oracle_for('signed'), cr.universe_U('signed'),
     [{('Non', 'sk_A'), ('Unq', 'N')}], 3),
    ('two-key variant', cr.oracle_for('twokey'), cr.universe_U('twokey'),
     [{('Non', 'k1'), ('Unq', 'N')}, {('Non', 'k2'), ('Unq', 'N')}], 4),
    ('Needham-Schroeder', nspk_oracle(False), [skA, skB], [], None),
    ("Lowe's fix (NSL)", nspk_oracle(True), [skA, skB], [{skA}], None),
]


def fmt_fam(F):
    if not F:
        return 'false'
    return ', '.join('{' + ', '.join('%s(%s)' % a for a in sorted(T)) + '}'
                     for T in sorted(F, key=lambda T: sorted(T)))


def run_row(label, oracle, U, want, want_calls, shrink=False):
    t0 = perf_counter()
    W, H, st = weakest(oracle, U=U, shrink=shrink)
    dt = perf_counter() - t0
    ok = set(map(frozenset, W)) == set(map(frozenset, want))
    calls_ok = '' if want_calls is None else ('  (paper: %d %s)' % (
        want_calls, 'match' if st['distinct'] == want_calls else 'MISMATCH'))
    print('%-18s W = %s' % (label, fmt_fam(W)))
    print('%-18s H = %s' % ('', fmt_fam(H) if H != [frozenset()] else '{{}} (empty stopping set)'))
    print('%-18s distinct calls = %d (shrink %d), loop queries without memo = %d, time = %.2fs, '
          'W matches Table 2: %s%s' % ('', st['distinct'], st['shrink'], st['total'], dt,
                                        'yes' if ok else 'NO', calls_ok))
    return ok


def main():
    print('Table 2, analyser rows (oracle witness = first DFS attack, pruned to a minimal run)')
    print('-' * 100)
    allok = all([run_row(*row) for row in ROWS])
    if '--ablation' in sys.argv:
        print()
        print('Ablation: challenge-response rows with the DFS witness run as found (not pruned)')
        print('-' * 100)
        for proto, (label, _, U, want, n) in (('signed', ROWS[0]), ('twokey', ROWS[1])):
            raw = cr.oracle_for(proto, minimal_run=False)
            run_row(label + ' raw', raw, U, want, n)
            run_row(label + ' raw+shr', raw, U, want, n, shrink=True)
    print()
    print('all W(chi) match Table 2' if allok else 'SOME W(chi) DIFFER FROM TABLE 2')


if __name__ == '__main__':
    main()
