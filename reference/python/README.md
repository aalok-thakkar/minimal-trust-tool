# Python reference implementation

The Python prototype from which the OCaml tool was ported. It is kept here because the
differential tests (`test/diff_python.sh`, `test/diff_bounded.sh`) and the CPSA ground-truth
scripts (`cpsa/selection/evaluate.py`, `cpsa/selection/oracle_fixed.py`) import it
read-only. It is not modified; one known defect in `cpsa/cpsa_oracle.py` (the replay check)
is corrected by a subclass in `cpsa/selection/oracle_fixed.py`, see
`cpsa/protocols/MANIFEST.md`, "Replay check".

Python 3 (tested on 3.13), standard library only. Run the commands below from this
directory. "Table 2" refers to the conference version of the paper.

## Reproduce Table 2 (analyser rows)

    python3 reproduce.py              # signed CR, two-key, Needham-Schroeder, NSL (about 25 s)
    python3 reproduce.py --ablation   # also: unpruned witnesses, with and without shrinking

For each row it prints W(chi), the recovered minimal attacks H, the number of distinct
oracle calls, the number of candidate queries the unmemoised loop would make, and time.
Expected output (times vary):

    signed CR          W = {Non(sk_A), Unq(N)}
                       H = {Non(sk_A)}, {Unq(N)}
                       distinct calls = 3 (shrink 0), loop queries without memo = 3, ...
    two-key variant    W = {Non(k1), Unq(N)}, {Non(k2), Unq(N)}
                       H = {Non(k1), Non(k2)}, {Unq(N)}
                       distinct calls = 4 (shrink 0), loop queries without memo = 4, ...
    Needham-Schroeder  W = false
                       H = {{}} (empty stopping set)
                       distinct calls = 2 (shrink 0), loop queries without memo = 2, ...
    Lowe's fix (NSL)   W = {Non(sk_A)}
                       H = {Non(sk_A)}
                       distinct calls = 2 (shrink 0), loop queries without memo = 2, ...

The PKINIT rows use CPSA (see `cpsa/` and `pkinit_mintrust.py`).

## Other entry points

    python3 dy.py; python3 hitting.py; python3 cegis.py   # unit self-tests
    python3 run.py                      # NSPK/NSL regression checks
    python3 cr.py [proto ...]           # enumerate all attack states of the CR models under
                                        # the empty trust, grouped by stopping set

## Files

* `dy.py` bounded Dolev-Yao term algebra and derivability.
* `hitting.py` clutters, minimal transversals, blocker.
* `cegis.py` Algorithm 1. `weakest(oracle, U=None, shrink=False)` returns
  `(W, H, stats)` with a memo table keyed on the frozenset trust; `stats` has `distinct`
  (oracle calls made), `total` (candidate queries the unmemoised loop makes) and `shrink`.
  `shrink_witness` minimalises a witness stopping set (notes_minimal.md). `cegis(oracle)`
  keeps the original interface and stores the counts in `cegis.LAST_STATS`. Candidates are
  queried smallest first, then in lexicographic order, so counts are deterministic.
* `analyzer.py` bounded oracle for Needham-Schroeder and NSL.
* `cr.py` bounded oracles for the signed challenge-response and its two-key variant, plus
  two probe variants without names (`signed_nonames`, `shared_nonames`).
* `channels.py` NSPK/NSL with authentic and confidential channel generators.
* `composition.py` the composition experiment (two protocols sharing keys).
* `pkinit_mintrust.py` PKINIT rows by exhaustive CPSA evaluation; `cpsa/` the CPSA oracle
  (see `cpsa/README.md`).
* `reproduce.py` the Table 2 analyser rows. `listing1.txt` the revised Listing 1.
* `notes_bounds.md` analyser bounds; `notes_minimal.md` non-minimal witnesses.

## Analyser bound (summary of notes_bounds.md)

Intruder: Dolev-Yao network; receives are role templates with variables bound to atoms
from a fixed pool (no type flaws), accepted if derivable; derivability is decided exactly
within the subterms of the knowledge and the target. Search: depth-first over
interleavings with state deduplication; a pass means the whole bounded space has no attack.

* Signed CR / two-key: one instance each of Chal(B,A) (test), Prov(A,B), Prov(B,A),
  Chal(A,B), Prov(A,I), plus one earlier completed Prov(A,B) session on N_old whose
  transcript the intruder holds. Without Unq(N) the test nonce may be N_old. Goal: recent
  agreement (Prov(A,B) answered N_t after the test strand sent it). Variable pool
  {A, B, I, N, N_old, N_a}; template depth 3 (signed) and 4 (two-key). The fresh test nonce
  is searched before the stale one; the first attack is pruned to a minimal run.
* NSPK / NSL: one instance each of Init(A,B), Init(A,I), Resp(B,A) (test); variable pool
  {A, B, I, Na_0, Na_1, Nb_2}; template depth 3; freshness supplied by the situation.
  Goal: non-injective agreement of Resp(B,A) with Init(A,B) on (Na, Nb).

Attacks found are genuine runs, so necessity of every reported atom holds without bound;
sufficiency holds relative to the pool. Needham-Schroeder's `false` is unconditional.
