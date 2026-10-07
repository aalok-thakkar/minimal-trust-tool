# minimal-trust-tool

The OCaml tool for the paper *Trust a Few: The Weakest Assumptions a Protocol Needs*
(Bhumika Mittal and Aalok Thakkar; extended version on arXiv; conference version
*The Trust a Protocol Needs*, ICISS 2026).

A security protocol achieves its goal only under assumptions: some keys are not
compromised, some values are fresh, some channels are authentic or confidential. Given a
protocol, a goal, and a finite set U of such assumptions (the candidate assumptions), the tool
computes the weakest trust the protocol needs: every minimal subset of U under which the
goal holds (the family W), together with the minimal attacks (the family H, whose
minimal transversals are W). It uses a counterexample-guided loop (Algorithm 1 of the
paper) over a protocol verifier used as an oracle. Each candidate trust is checked by
the verifier; a failing check returns an attack, the attack's stopping set (the
assumptions that would rule it out) is added to H, and the next candidates are the
minimal transversals of H. With minimal witnesses the loop makes at most |W| + |H|
verifier calls.

Two oracles are included: a bounded Dolev-Yao analyser written in OCaml, and
[CPSA](https://hackage.haskell.org/package/cpsa) 4.4.9 driven as an external process.

Example (`dune exec -- trust selftest`; the signed challenge-response of Section 2 of
the paper with U = {Non(sk_A), Unq(N)}, and its two-key variant):

```
signed CR: W = [{Non(sk_A), Unq(N)}], H = [{Non(sk_A)}, {Unq(N)}], distinct=3 queries=3 ...
two-key:   W = [{Non(k1), Unq(N)}, {Non(k2), Unq(N)}], H = [{Unq(N)}, {Non(k1), Non(k2)}], distinct=4 ...
```

The first protocol needs both an uncompromised signing key and a fresh challenge; the
two-key variant needs a fresh challenge and either one of its two keys.

## Requirements

- OCaml 5.1 and dune >= 3.0, for example through opam:

  ```
  opam switch create 5.1.0
  eval $(opam env --switch=5.1.0)
  opam install dune
  ```

  The library uses only the standard library and `unix`.

- Optional: CPSA 4.4.9, for the CPSA oracle, the CPSA integration tests and the
  experiments on the CPSA rows. Install from Hackage with GHC and cabal-install:

  ```
  cabal get cpsa-4.4.9 && cd cpsa-4.4.9
  cabal install exe:cpsa4 --allow-newer=cpsa:deepseq \
      --installdir=$HOME/.local/bin --install-method=copy --overwrite-policy=always
  ```

  `--allow-newer=cpsa:deepseq` is needed with GHC 9.12, whose boot package deepseq 1.5
  is outside the bound `deepseq < 1.5` declared by cpsa-4.4.9; no source change is
  needed. The tool finds the binary as `$CPSA4` if set, else `cpsa4` on `PATH`, else
  `~/.local/bin/cpsa4`. Without it, the CPSA integration tests print a skip message and
  pass.

- Optional: Python 3 (standard library only; tested with 3.13), for the table scripts,
  the differential tests against the Python reference, and the CPSA ground-truth
  scripts.

## Build and test

```
dune build --profile release
dune test --force                 # unit, property and CPSA tests (about 10 s)
dune exec -- trust selftest       # end-to-end check of the core library
```

Differential tests against the Python reference in `reference/python/` (need Python 3;
run from the repository root):

```
sh test/diff_python.sh            # Clutter and Loop on 300 random clutters (about 1 s)
sh test/diff_python.sh SEED SMALL LARGE   # defaults: 2026 200 100
sh test/diff_bounded.sh           # bounded analyser, every row and trust (10 to 15 min)
python3 test/diff_cpsa.py results/final/cpsa_rows.csv
                                  # CPSA rows against cpsa/selection/results/*.json
```

What the tests cover:

- `test/test_trust.ml`: the self-tests of the Python `hitting.py`, `cegis.py` and `dy.py`;
  the Section 2 answers via mock oracles; the soundness exceptions; seeded property
  tests of the blocker (involution, agreement with brute-force minimal transversals up to
  n = 16), of `minimalize`, and of `Loop.weakest` against brute force on random monotone
  oracles in three witness modes, including the call bounds; the baselines.
- `test/test_bounded.ml`: the bounded analyser (derivability against `Dy`, analyser
  rows, composition, witness replay, monotonicity, state-space reductions).
- `test/scale/test_scale.ml`: synthetic families and the gadget protocol.
- `test/test_cpsa.ml`: S-expression parsing and verdict reading on a saved CPSA output,
  replay-input construction, completeness detection, the corrected replay check; an
  integration test on PKINIT (flawed and fixed) that is skipped when `cpsa4` is absent.
- `test/diff_python.sh`, `test/diff_bounded.sh`: the same random clutters and protocol
  rows through the Python reference and this library; families compared as sets and
  call counts compared exactly.
- `test/diff_cpsa.py`: `trust cpsa` output against the Python ground truth
  (exhaustive W and A; per witness mode W, H, distinct calls, queries, shrink calls,
  CPSA goal runs and replay runs).

## Quick start

There are two executables, `trust` and `trust-exp`. Each experiment writes CSV files and
a log into `--out DIR`.

```
dune exec --release -- trust cpsa --out results/mine
    # E1, E2, E4 on the CPSA rows: exhaustive lattice vs Algorithm 1, call counts, timing
dune exec --release -- trust cpsa --only pkinit-flawed,pkinit-fix2 --no-timing --out results/mine
    # the same on selected rows, without the timing repetitions (a few seconds)
dune exec --release -- trust scale --quick
    # E3 smoke test: synthetic families and the gadget check (under a minute; results/quick)
dune exec --release -- trust scale --phase counts,gadget --jobs 10 --out results/mine
    # E3 call counts in parallel forked children, and the gadget validity check
dune exec --release -- trust scale --phase timing --out results/mine
    # E3 timing, one child at a time
dune exec --release -- trust-exp rows --out results/mine
    # E1, E2 on the bounded-analyser rows, in every witness mode
dune exec --release -- trust-exp channels --out results/mine
    # E6: NSPK and NSL with authentic and confidential channel generators
dune exec --release -- trust-exp compose --out results/mine
    # E7: composition of two protocols that share a signing key
dune exec --release -- trust-exp bound --out results/mine
    # E5: sensitivity of the bounded analyser's answers to the instance pool
```

Experiments:

| id | question | command |
|---|---|---|
| E1 | does Algorithm 1 return the exhaustive answer? | `trust cpsa`, `trust-exp rows` |
| E2 | how many oracle calls, against the bound \|W\| + \|H\|? | `trust cpsa`, `trust-exp rows` |
| E3 | how do calls and time grow on synthetic families? | `trust scale` |
| E4 | wall time against the exhaustive, levelwise and greedy baselines on CPSA rows | `trust cpsa` |
| E5 | how do the bounded analyser's answers change with the pool size? | `trust-exp bound` |
| E6 | channel assumptions as generators | `trust-exp channels` |
| E7 | composition | `trust-exp compose` |

## Reproducing the paper's results

```
sh scripts/run_all.sh
```

runs every step in sequence and writes into `results/final/`: the test suite, the three
differential tests, `trust-exp rows`, `channels`, `compose`, `trust cpsa`, `trust scale`
(counts and gadget with 10 parallel jobs, then timing) and `trust-exp bound`. Each
step's output goes to `results/final/<step>.stdout`; `run_all.log` records start, end
and load average per step; `manifest.txt` records machine, OS, compiler and CPSA
versions. On an Apple M3 Max (14 cores) the run took about 3 h 40 min, mostly in the
scale counts (1 h 20 min), scale timing (45 min) and bound study (1 h 20 min); the CPSA
step takes about 3 minutes and the bounded differential test 10 to 15 minutes. Keep the
machine otherwise idle during the timing steps. The script reads machine information
with macOS commands (`sysctl`, `sw_vers`); on other systems those manifest fields are
left empty. `scripts/run_scale.sh` runs the scale study alone.

`results/final/` holds the data reported in the paper. The CPSA step was rerun alone
after a template was added (`manifest_cpsa.txt` records that run), so its timings and
load come from the rerun, and `manifest.txt` describes the full run before it.

Tables are generated from the CSVs; no number in them is typed by hand:

```
python3 scripts/make_tables.py results/final
    # tab_results.tex, tab_bound.tex, tab_composition.tex, numbers.tex (conference version)
python3 scripts/scale_table.py results/final            # tab_scale.tex
python3 scripts/scale_table.py --short results/final    # tab_scale_short.tex
python3 scripts/make_tables_long.py results/final
    # long_*.tex tables and macros (arXiv version), into results/final/tables/
```

Verdicts, W, H and call counts are deterministic and must match the published data
exactly; times depend on the machine.

## Repository layout

```
lib/                library `trust`
  aset, clutter       trust sets, clutters, minimalisation, blocker (Berge's algorithm)
  term, dy            Dolev-Yao terms and derivability
  loop                Algorithm 1 (Loop.weakest) and baselines B1 (exhaustive),
                      B2 (levelwise), B3 (greedy)
  bounded, protocols  bounded strand-space analyser and its protocol rows
  cpsa                CPSA 4.4.9 driver and oracle
  synth, gadget       synthetic families and the gadget protocol of Appendix A (E3)
bin/                `trust`: selftest, cpsa, scale
bin/exp/            `trust-exp`: rows, channels, compose, bound
test/               dune tests and differential tests
cpsa/protocols/     CPSA templates of the protocol rows, format README, MANIFEST.md
cpsa/selection/     Python ground truth for the CPSA rows (evaluate.py, oracle_fixed.py,
                    results/), and the excluded candidates
reference/python/   Python reference implementation, read by the differential tests
scripts/            run_all.sh, run_scale.sh, table generators
results/final/      published experiment data and generated tables
```

Each `lib/*.mli` documents its module. Every family the library returns is
duplicate-free and in a canonical order (size, then lexicographic), and Algorithm 1
queries candidates in that order, so call counts are deterministic.

Implementation notes:

- `Clutter.minimalize` sorts by size, then checks each set against strictly smaller kept
  sets through an inverted index with counters (no pairwise subset scan).
- `Clutter.blocker` is Berge's incremental algorithm. Each step keeps the parts that meet
  the new edge and extends the others by one atom of the edge; an extension is dropped
  iff it contains a staying part, found by the same counting index. The step's output is
  already a clutter (argument in `clutter.ml`).
- `Loop.weakest` raises `Loop.Unsound_witness` if a stopping set is not inside U, meets
  the trust it fails, or contains a member of the current H; in shrink mode, if a
  witness for `u \ (S \ {a})` is not inside `S \ {a}`.
- `stats.distinct` counts oracle calls (including shrink calls); `stats.queries` counts
  main-loop candidate evaluations including memo hits.

## CPSA protocol models

`cpsa/protocols/` holds one template per CPSA row: PKINIT (flawed and fixed), Yahalom,
Otway-Rees (two variants), Denning-Sacco, Kerberos (two goals), Neuman-Stubblebine,
ISO 9798-3 (flawed and fixed), and Blanchet (flawed and fixed). A template is valid CPSA
input once its placeholder is replaced:

```
;; @name <row name>
;; @source <where the protocol text is from>
;; @U <atom-id> <fact>              one line per generator, e.g. (non (privk a))
(defprotocol <name> basic ...)       protocol text, passed to CPSA unchanged
(defgoal <name>
  (forall (...)
    (implies (and <situation> @TRUST@) <conclusion>)))
```

For a trust T, `@TRUST@` is replaced by the facts of T. `cpsa/protocols/README.md`
gives the full format and how a CPSA run is read as a verdict and as a stopping set.
`cpsa/protocols/MANIFEST.md` records how the rows were selected, the excluded
candidates, the ground truth, and a defect found in the Python reference's replay check
(corrected in `lib/cpsa.ml` and in `cpsa/selection/oracle_fixed.py`).

## Extending

**A CPSA protocol.** Write `cpsa/protocols/<name>.scm` in the template format, with one
`@U` line per generator and `@TRUST@` in the goal's hypothesis. Then
`trust cpsa --only <name> --no-timing --out DIR` runs the exhaustive lattice and
Algorithm 1 on it. `python3 cpsa/selection/evaluate.py <name>` writes the Python ground
truth `cpsa/selection/results/<name>.json` used by `test/diff_cpsa.py`.

**A bounded-analyser protocol.** Add a row to `lib/protocols.ml` as a `Bounded` model
(strands, generators, goal), following the existing rows.

**An oracle.** An oracle is a function from a trust (`Aset.t`) to `Loop.answer`:
`Achieves`, or `Fails { stops; descr }`, where `stops` is the set of generators whose
assumption would rule out the attack found. Pass it to `Loop.weakest ~u oracle`;
`lib/loop.mli` describes the soundness checks and the shrink option for non-minimal
witnesses.

## Citation

```bibtex
@misc{mittal2026trustafew,
  author        = {Bhumika Mittal and Aalok Thakkar},
  title         = {Trust a Few: The Weakest Assumptions a Protocol Needs},
  year          = {2026},
  eprint        = {XXXX.XXXXX},
  archivePrefix = {arXiv},
  primaryClass  = {cs.CR}
}

@inproceedings{mittal2026trust,
  author    = {Bhumika Mittal and Aalok Thakkar},
  title     = {The Trust a Protocol Needs},
  booktitle = {Information Systems Security (ICISS 2026)},
  year      = {2026}
}
```

The arXiv identifier is a placeholder until the preprint is posted. `CITATION.cff` has
the same information.

## License

MIT; see `LICENSE`. The protocol texts in `cpsa/protocols/` are taken from the test
suite distributed with CPSA 4.4.9 (`tst/`), as recorded in each template's `@source`
line.
