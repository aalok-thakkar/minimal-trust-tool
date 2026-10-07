# CPSA protocol templates

One file per CPSA row of the experiments. Every file has the same format, so the OCaml
driver (`Cpsa`) and the Python selection scripts read them the same way. Selection,
ground truth and the list of excluded candidates are in `MANIFEST.md`.

## Format

```
;; @name <row name>                      required, once
;; @source <where the protocol text is from>
;; @goal <shipped | written>: <one line>
;; @note <free text>                     any number
;; @U <atom-id> <fact>                   one line per generator, in the order of U
...
(defprotocol <name> basic ...)           passed to CPSA unchanged
(defgoal <name>
  (forall (...)
    (implies
      (and <situation atoms>
           @TRUST@)                      the placeholder
      <conclusion>)))
```

- Header lines start with `;; @` and are CPSA comments, so a template is valid CPSA input
  once the placeholder is replaced.
- `@U` lines define the generators U. `<atom-id>` is a token (`[A-Za-z0-9_]+`) used in
  results and tables; `<fact>` is a CPSA goal fact over the goal's universally quantified
  variables, either `(non <term>)` or `(uniq <term>)`. Every variable a fact uses is bound in
  the hypothesis by a `(p "role" "var" z var)` atom.
- `@TRUST@` occurs exactly once, inside the hypothesis conjunction of the single `defgoal`,
  and nowhere in the protocol text. For a trust T (a subset of U) it is replaced by the
  facts of T separated by whitespace; the empty trust replaces it by the empty string.
- The protocol text is everything before `(defgoal` (header lines removed). The replay
  check of the stops recipe (`reference/python/cpsa/notes_stops.md`) needs it alone, without the
  goal.
- CPSA input for trust T is `(herald "<name> trust")`, the protocol text, and the goal with
  the placeholder replaced. No CPSA options are passed (defaults: step limit 2000, strand
  bound 12).
- Role-level declarations (`uniq-orig`, `non-orig` inside a `defrole`) are part of the
  situation, not of U, and stay in the protocol text.

## Reading a verdict

Achievement at T: CPSA ends with `Nothing left to do`, reports no step-limit or
strand-bound abort, and no shape carries `(satisfies (no ...))`. A run that does not end
that way is an error, not a verdict.

Replay check (for stops(x)): a shape x survives the added atoms M iff the first skeleton
CPSA prints for the replay input (label 0) is `(realized)` and carries neither
`(preskeleton)` nor `(dead)`. The second condition is missing from
`reference/python/cpsa/cpsa_oracle.py`; see MANIFEST.md, "Replay check".

## Files

Rows: `pkinit-flawed`, `pkinit-fix2`, `yahalom` (existing rows, re-derived),
`otway-rees`, `denning-sacco`, `kerberos`, `neuman-stubblebine`, `isoreject`, `isofix`,
`blanchet`, `blanchet-fixed` (new).

Excluded candidates and diagnostic variants use the same format and live in
`../selection/candidates/`.

In the `@source` lines, `artifact/` names the Python reference implementation, shipped in
this repository as `reference/python/`. The templates are kept byte-identical to the files
used for the published runs, so their md5 sums match `results/final/manifest_cpsa.txt`.
