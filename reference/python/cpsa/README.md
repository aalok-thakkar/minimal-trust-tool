# CPSA oracle for Algorithm 1

Files:

- `cpsa_oracle.py`: CPSA 4 as the achievement oracle, with stops(x) computed from CPSA's
  shapes (recipe in `notes_stops.md`).
- `run_cegis.py`: runs Algorithm 1 (`../cegis.py`, unchanged) with that oracle on PKINIT
  (flawed, fixed) and, given `yahalom` as argument, on Yahalom. Output: `run_cegis.out`.
- `protocols.py`: Yahalom, protocol text from CPSA's `tst/yahalom.scm`, with a responder
  agreement goal and four generators.
- `lattice_check.py`: evaluates achievement at every point of 2^U, no loop. Output:
  `lattice_check.out`.
- `pkinit_mintrust.out`: output of `../pkinit_mintrust.py` (the original Table 2 run).
- `example_pkinit_flawed_fulltrust.{scm,out}`: CPSA input and output for flawed PKINIT under
  both `non` facts, showing the Cervesato shape and its `(satisfies (no ...))` annotation.

## CPSA

- Version: CPSA 4.4.9 (Hackage `cpsa-4.4.9`), `cpsa4 --version` prints `CPSA 4.4.9`.
- Toolchain: GHC 9.12.1, cabal-install 3.14.1.1 (Homebrew), macOS 26.5.2 arm64, Python 3.13.2.
- Build:

  ```
  cd ~/.local/src && cabal get cpsa-4.4.9 && cd cpsa-4.4.9
  cabal install exe:cpsa4 --allow-newer=cpsa:deepseq \
      --installdir=$HOME/.local/bin --install-method=copy --overwrite-policy=always
  ```

  `--allow-newer=cpsa:deepseq` is needed because cpsa-4.4.9 declares `deepseq < 1.5` and
  GHC 9.12.1 ships deepseq 1.5.1.0 as a boot package; without it the solver fails with
  `rejecting: bytestring-0.12.2.0/installed-inplace (conflict: cpsa => deepseq>=1.4.8 && <1.5,
  bytestring => deepseq==1.5.1.0/installed-inplace)`. No source was changed.
- Binary lookup (all scripts, including `../pkinit_mintrust.py`): `$CPSA4` if set, else
  `cpsa4` on `PATH`, else `~/.local/bin/cpsa4`.
- Options: none passed, so CPSA defaults apply: step limit 2000 (`-l`), strand bound 12
  (`-b`), unbounded depth, basic algebra. Every goal run and replay run used here ends with
  `Nothing left to do`; `cpsa_oracle.py` raises an error on any run that does not, or that
  reports `Step limit exceeded` / `Strand bound exceeded`, so no answer below depends on a
  truncated search. (`../pkinit_mintrust.py` does not perform this check; its four runs per
  protocol were checked by the oracle here.)

## Reproduce

```
cd reference/python
python3 pkinit_mintrust.py          # Table 2 PKINIT rows, full lattice
python3 cpsa/run_cegis.py yahalom   # Algorithm 1 with CPSA as oracle
python3 cpsa/lattice_check.py       # exhaustive cross-check
```

## Results and run times (Apple silicon laptop, wall clock)

| run | result | CPSA runs | time |
|---|---|---|---|
| `pkinit_mintrust.py`, flawed | false (all 4 points attacked) | 4 | 0.19 s total for both protocols |
| `pkinit_mintrust.py`, fixed | {non(privk as)} | 4 | (included above) |
| loop, PKINIT flawed | false | 2 goal + 3 replay | 0.10 s |
| loop, PKINIT fixed | {non(privk as)} | 2 goal + 2 replay | 0.08 s |
| loop, Yahalom | {non(ltk a c), non(ltk b c)} | 3 goal + 10 replay | 0.35 s |
| lattice, PKINIT flawed / fixed / Yahalom | false / {non_as} / {non_ltk_ac, non_ltk_bc} | 4 / 4 / 16 | 0.09 / 0.08 / 0.75 s |

`non_as` is `(non (privk as))`, sk(S) in the paper; `non_c` is `(non (privk c))`, sk(C).
Individual CPSA runs take 0.02 to 0.03 s.
