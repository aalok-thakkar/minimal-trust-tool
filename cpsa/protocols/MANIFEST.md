# CPSA protocol set for RQ1 (Stage 1')

CPSA 4.4.9 (`~/.local/bin/cpsa4`, no options, so step limit 2000 and strand bound 12),
Apple M3 Max, macOS, Python 3.13. Run 2026-10-04. All numbers below come from
`../selection/results/*.json` (regenerate with `python3 ../selection/evaluate.py`; tables with
`python3 ../selection/table.py rows|cands|goals`). Nothing in `reference/python/` (the Python
reference, imported read-only) was edited. In the `@source` lines of the templates and in
`../selection/results/*.json`, `artifact/` names that reference; the templates are kept
byte-identical to the runs, so their md5 sums match `results/final/manifest_cpsa.txt`.

## Row set (16 rows)

| # | row | oracle | source | status |
|---|---|---|---|---|
| 1 | signed CR | bounded analyser | paper Section 2 | existing |
| 2 | two-key variant | bounded analyser | paper Section 2 | existing |
| 3 | NSPK | bounded analyser | | existing |
| 4 | NSPK + channels | bounded analyser | | existing |
| 5 | NSL | bounded analyser | | existing |
| 6 | pkinit-flawed | CPSA | tst/pkinit.scm | existing, template re-derived |
| 7 | pkinit-fix2 | CPSA | not in tst/ (reference/python/pkinit_mintrust.py) | existing, template re-derived |
| 8 | yahalom | CPSA | tst/yahalom.scm | existing, template re-derived |
| 9 | otway-rees | CPSA | tst/or.scm | new |
| 10 | denning-sacco | CPSA | tst/denning-sacco.scm | new |
| 11 | kerberos | CPSA | tst/kerberos.scm | new |
| 12 | neuman-stubblebine | CPSA | tst/neuman-stubblebine.scm | new |
| 13 | isoreject | CPSA | tst/isoreject.scm | new |
| 14 | isofix | CPSA | tst/isoreject-corrected.scm | new |
| 15 | blanchet | CPSA | tst/blanchet.scm | new |
| 16 | blanchet-fixed | CPSA | tst/blanchet.scm | new |

Rows 1-5 are outside this directory and were not re-run here.

## Inclusion rule, as applied

The selection rule, fixed before the evaluation, and how each clause was made mechanical:

1. **Source.** A protocol shipped in CPSA 4.4.9's `tst/` (`*.scm`, `*.lsp`), protocol text
   unchanged. Preferred list: Otway-Rees, Woo-Lam, Denning-Sacco,
   Needham-Schroeder symmetric key, Kerberos (basic), ISO 9798-3 variants, Wide-Mouthed
   Frog, Neuman-Stubblebine, Andrew secure RPC, TLS-like handshake. Every preferred
   protocol that is shipped was evaluated. Protocols outside the list were considered only
   for slots the list left open (clause 6).
2. **Goal.** A safety goal in the fragment: non-injective agreement of one role with
   another, or secrecy, as a CPSA `defgoal` whose hypothesis carries the trust as `non` /
   `uniq` facts. If the file has a `defgoal` for the protocol, it is used with its trust
   facts replaced by the placeholder. Otherwise the goal is written: the observed role is
   the role of the file's first `defskeleton` for that protocol (or, where the file has one
   skeleton per role, the responder), the hypothesis fixes that role's completed strand and
   binds its parameters, and the conclusion is the standard agreement goal (a strand of the
   partner role, at the last position the observed role's evidence can imply, agreeing on
   the names and the session key or nonce named in the "goal" column). When the file's
   analysis is a secrecy query (a skeleton with a `deflistener`), the goal is secrecy of
   that value. Every written goal is marked `@goal written` in its template.
3. **U.** `non` over each long-term key of a principal named by the observed role that
   occurs in the protocol (`ltk x s`, `privk x`); `uniq` over each nonce, timestamp or
   session key among the observed role's parameters that no role declares `uniq-orig`.
   Not in U: names, lifetimes and free-text fields, and every role-level `non-orig` /
   `uniq-orig` (these stay in sigma, as for Yahalom and PKINIT).
4. **Termination.** CPSA with defaults must finish, ending with `Nothing left to do` and
   no step-limit or strand-bound abort, at every one of the 2^|U| points within 60 s per
   run.
5. **Size.** |U| between 2 and 8; |U| < 2 is excluded (a 2-point lattice tests nothing).
6. **Cap.** 16 rows in total, so at most 8 new. Preferred-list protocols first; then
   secondary candidates that add a goal class not otherwise covered (secrecy).
7. **Equational theories** (DH, XOR; A5) excluded: `sts*`, `dh*`, `DH_hack`,
   `dhstatic-state`, `dh_group_sig*` were not considered.

Two judgement calls, stated so they can be reversed:

- *First pass of clause 3.* The first pass put `uniq` on every `text`-sorted parameter
  (sort rule). That added `uniq l` (ticket lifetime) to Kerberos and `uniq t1/t2/t3` (the
  ISO Text fields) to iso-unilateral, which are not nonces. Applying the rule's wording
  removed them; Kerberos keeps |U| = 4 with the same W, and iso-unilateral drops to
  |U| = 1 and out (clause 5). Both first-pass versions are kept and evaluated in
  `../selection/candidates/` (`kerberos-sortrule`, `iso-unilateral`).
- *Clause 6.* Seven preferred-list protocols qualified, leaving one slot; the Blanchet
  pair (flawed and fixed) was taken as two rows because it supplies the only secrecy goal
  and mirrors the PKINIT flawed/fixed pair. This makes the total 16. With the sort rule of
  the first pass, iso-unilateral would also have qualified (17 rows).

## Candidates considered

| candidate | tst/ file | decision | reason |
|---|---|---|---|
| Otway-Rees | or.scm | included | |
| Woo-Lam | woolam.scm (`woolam`) | excluded | U = {non(ltk a s)}, \|U\| = 1: the resp role declares `non-orig (ltk b s)` and `uniq-orig n`. W = {non(ltk a s)}, 2 points, 0.04 s |
| Denning-Sacco | denning-sacco.scm | included | |
| Needham-Schroeder symmetric key | none | not shipped | `nslsk.scm` is NSL with a symmetric session key, a different protocol |
| Kerberos (basic) | kerberos.scm | included | |
| ISO 9798-3, three-pass | isoreject.scm, isoreject-corrected.scm | both included | flawed / fixed pair |
| ISO 9798-3, two-pass unilateral | unilateral.scm (`iso-unilateral`) | excluded | shipped goal; U = {non(privk b)}, \|U\| = 1 (t1-t3 are Text fields). First-pass U of size 4 gives W = {non_privk_b} |
| Wide-Mouthed Frog | wide-mouth-frog.lsp | excluded | no answer within 60 s at the 4 points containing both non atoms (see below); the file's herald notes infinitely many shapes and sets `(bound 8)` |
| Wide-Mouthed Frog (Scyther) | wide-mouth-frog-scyther.lsp | not run | same herald note; same structure as the above |
| Neuman-Stubblebine | neuman-stubblebine.scm | included | |
| Neuman-Stubblebine reauth | neuman-stubblebine-reauth.lsp | not run | herald sets `(bound 8)`; the basic protocol is already a row |
| Andrew secure RPC | none | not shipped | |
| TLS-like handshake | none | not shipped | |
| Blanchet | blanchet.scm (`blanchet`, `blanchet-fixed`) | both included | secondary; secrecy goal (clause 6) |
| NSPK, NSL (CPSA versions) | ns.scm, ns-l.scm, goals.scm | not added | already rows 3-5 (bounded analyser) |
| Yahalom variants | yahalom-6.3.6.scm, yahalom-forward.scm, chan-*.scm | not added | Yahalom is row 8; chan-* use channel sorts |
| DASS, NSL3, NSL-SK, EPMO, Fluffy GSKE, Wang | dass_simple.scm etc. | not evaluated | secondary; no slot left after clause 6 |
| DH/STS family | sts*.scm, dh*.scm | excluded | equational theory (A5) |

## Results

Columns: |A| / N is |attacks(chi)| (the blocker of W) and N = |attacks| + |weakest|,
the call bound of Theorem 9 for minimal witnesses. Loop entries: "=" means the loop's answer
equals the exhaustive W, then distinct oracle calls (CPSA goal runs g + replay runs r).
"ref loop" is `reference/python/cpsa/cpsa_oracle.py` unchanged; "fixed loop" adds the replay
correction below; "shrink" minimalises each witness before it enters H (cegis.weakest,
shrink=True). CPSA time is the sum and the maximum over the lattice points (wall clock,
single run, no repetitions).

| row | \|U\| | U | points | W(chi) (exhaustive) | \|A\| / N | CPSA s total / max | warnings | ref loop | fixed loop | fixed loop, shrink |
|---|---|---|---|---|---|---|---|---|---|---|
| pkinit-flawed | 2 | non_as, non_c | 4 | false | 1 / 1 | 0.07 / 0.02 | none | = 2 (2g+3r) | = 2 (2g+3r) | = 2 (2g+2r) |
| pkinit-fix2 | 2 | non_as, non_c | 4 | {non_as} | 1 / 2 | 0.07 / 0.02 | none | = 2 (2g+2r) | = 2 (2g+2r) | = 3 (3g+2r) |
| yahalom | 4 | non_ltk_ac, non_ltk_bc, uniq_na, uniq_nb | 16 | {non_ltk_ac, non_ltk_bc} | 2 / 3 | 0.68 / 0.22 | none | = 3 (3g+10r) | = 3 (3g+10r) | = 4 (4g+10r) |
| otway-rees | 4 | non_ltk_as, non_ltk_bs, uniq_m, uniq_nb | 16 | false | 1 / 1 | 0.84 / 0.15 | none | = 2 (2g+37r) | = 2 (2g+37r) | = 2 (2g+4r) |
| denning-sacco | 5 | non_privk_a, non_privk_b, non_privk_ks, uniq_k, uniq_ta | 32 | {non_privk_a} | 1 / 2 | 0.86 / 0.06 | none | = 3 (3g+37r) | = 3 (3g+37r) | = 4 (4g+11r) |
| kerberos | 4 | non_ltk_aks, non_ltk_bks, uniq_t, uniq_tp | 16 | false | 1 / 1 | 1.11 / 0.30 | none | = 4 (4g+20r) | = 4 (4g+20r) | = 3 (3g+6r) |
| neuman-stubblebine | 5 | non_ltk_aks, non_ltk_bks, uniq_ra, uniq_rb, uniq_tb | 32 | {non_ltk_aks, non_ltk_bks} | 2 / 3 | 0.75 / 0.06 | none | = 3 (3g+13r) | = 3 (3g+13r) | = 4 (4g+13r) |
| isoreject | 4 | non_privk_a, non_privk_b, uniq_na, uniq_nc | 16 | false | 1 / 1 | 0.30 / 0.02 | none | = 2 (2g+7r) | = 2 (2g+7r) | = 2 (2g+4r) |
| isofix | 4 | non_privk_a, non_privk_b, uniq_na, uniq_nc | 16 | {non_privk_a} | 1 / 2 | 0.30 / 0.02 | none | = 2 (2g+4r) | = 2 (2g+4r) | = 3 (3g+4r) |
| blanchet | 4 | non_privk_a, non_privk_b, uniq_s, uniq_d | 16 | false | 1 / 1 | 0.28 / 0.02 | none | = 4 (4g+12r) | = 4 (4g+12r) | = 3 (3g+5r) |
| blanchet-fixed | 4 | non_privk_a, non_privk_b, uniq_s, uniq_d | 16 | {non_privk_a, non_privk_b, uniq_s, uniq_d} | 4 / 5 | 0.28 / 0.02 | none | = 6 (6g+13r) | = 6 (6g+13r) | = 6 (6g+11r) |

Every lattice evaluation was complete (every run ended `Nothing left to do`, no abort), no
CPSA warnings or stderr output occurred, and achievement was monotone in T at every row
(checked: every superset of a sufficient trust is sufficient). The slowest single CPSA run
on any row took 0.30 s.

Excluded candidates and diagnostic variants (same columns; not rows):

| row | \|U\| | U | points | W(chi) (exhaustive) | \|A\| / N | CPSA s total / max | warnings | ref loop | fixed loop | fixed loop, shrink |
|---|---|---|---|---|---|---|---|---|---|---|
| woolam | 1 | non_ltk_as | 2 | {non_ltk_as} | 1 / 2 | 0.04 / 0.02 | none | = 2 (2g+1r) | = 2 (2g+1r) | = 2 (2g+1r) |
| wide-mouth-frog | 4 | non_ltk_at, non_ltk_bt, uniq_k, uniq_tb | 16 | incomplete: 4 of 16 points time out at 60 s | | | | | | |
| iso-unilateral (first-pass U) | 4 | non_privk_b, uniq_t1, uniq_t2, uniq_t3 | 16 | {non_privk_b} | 1 / 2 | 0.28 / 0.02 | none | = 2 (2g+4r) | = 2 (2g+4r) | = 3 (3g+4r) |
| kerberos-sortrule (first-pass U) | 5 | non_ltk_aks, non_ltk_bks, uniq_t, uniq_tp, uniq_l | 32 | false | 1 / 1 | 2.21 / 0.32 | none | = 4 (4g+27r) | = 4 (4g+27r) | = 3 (3g+7r) |
| kerberos-key (diagnostic) | 4 | non_ltk_aks, non_ltk_bks, uniq_t, uniq_tp | 16 | {non_ltk_aks, non_ltk_bks} | 2 / 3 | 1.08 / 0.30 | none | = 4 (4g+16r) | = 4 (4g+16r) | = 5 (5g+12r) |
| otway-rees-neq (diagnostic) | 4 | non_ltk_as, non_ltk_bs, uniq_m, uniq_nb | 16 | {non_ltk_as, non_ltk_bs, uniq_nb} | 3 / 4 | 0.66 / 0.12 | none | **WRONG: false**, 2 (2g+31r) | = 4 (4g+47r) | = 5 (5g+47r) |

Wide-Mouthed Frog: the 12 points without both non atoms fail in 0.02 s each; the 4 points
with both time out at 60 s. A single run at the full trust with a 900 s limit
(`../selection/results/wmf_probe_900s.txt`) ended after 200 s with `Strand bound exceeded`
on stderr and an `(aborted)` skeleton: the server strands chain without end (each server
output `{tb, a, k}ltk(b,t)` is again a valid server input with the roles swapped), as the
file's herald says. So the exclusion is not a matter of the 60 s limit; under CPSA
defaults no verdict exists at those points.

## Notes on the answers

**Four of the eight new rows have W = false.** Each was checked by reading the failing
shape under the full trust U.

- *isoreject: known attack.* B's responder strand accepts `{nc, nb, b}sk(a)`, which A
  produces as a *responder* in a session with peer b started by the adversary with
  `(b, nb)`: the two signed messages have the same format, so A's responder signature
  stands in for an initiator's. No initiator strand exists, with both keys uncompromised
  and both nonces fresh. The shipped `isoreject-corrected.scm` (row isofix) adds distinct
  tags `"first"` / `"second"` and its W is {non(privk a)}.
- *blanchet: known attack, by design* (the file's comment says so). A runs the initiator
  with a compromised peer b-0; the adversary re-encrypts A's signed key `{s}sk(a)` to b.
  The fix (row blanchet-fixed) puts b inside the signature; its W is all four atoms.
- *otway-rees: artefact of the goal I wrote.* All failing shapes under the full trust have
  a = b: B runs the responder with itself, and the server accepts B's own block
  `{nb, m, a, a}ltk(a,s)` in the initiator position, because with a = b the two blocks have
  the same form and key. These are genuine runs of the model, but I do not know of them as
  a published attack on Otway-Rees; they arise because the written goal does not exclude
  a = b. With a != b added to the situation (diagnostic `otway-rees-neq`: a rule
  `neq x x => false` in the protocol and `(fact neq a b)` in the hypothesis), W =
  {{non(ltk a s), non(ltk b s), uniq(nb)}}: freshness of B's nonce is needed, since without
  it the server's reply for another session that reused nb is accepted by B. The authors
  should decide which form the row takes; the mechanical one is listed.
- *kerberos: artefact of the shipped abstraction together with name agreement.* The
  keyserver's two tickets `{t, l, k, b}ltk(a,ks)` and `{t, l, k, a}ltk(b,ks)` have the same
  form, and the reply `{t'}k` names no one. In the failing shape the adversary hands the
  key-server message to an initiator B (peer a) with the tickets swapped, forwards B's
  authenticator to A acting as *responder*, and A's own responder answers A's initiator.
  A's initiator completes, but the responder that answered is A with peer b, not b with
  peer a, so agreement on (a, b) fails at every trust. The CPSA file's comment notes the
  a/b symmetry of the keyserver. This is a property of this simplified model, not a known
  attack on Kerberos V5. Weakening the conclusion to agreement on k alone (diagnostic
  `kerberos-key`) gives W = {{non(ltk a ks), non(ltk b ks)}}.

**Rows with W != false agree with expectation.** Denning-Sacco (the shipped version, which
already includes both names in the signed message, so not the Abadi-Needham variant):
the responder's agreement needs only sk(a); the server key is irrelevant because CPSA's
`pubk a` is a function of a, so certificates bind nothing. Neuman-Stubblebine and Yahalom:
both long-term keys, no freshness (the goal is non-injective). isofix: sk(a) only.
blanchet-fixed: all four atoms, the only row where W is the whole of U; |attacks| = 4
singletons.

**Calls exceed the minimal-witness bound N on several rows** (Theorem 9 assumes minimal
witnesses; CPSA shapes need not have minimal stopping sets): as-found calls / N =
denning-sacco 3/2, kerberos 4/1, blanchet 4/1, blanchet-fixed 6/5, kerberos-key 4/3.
Shrink mode does not always reduce distinct calls, because each shrink step is itself an
oracle call; it reduces replay runs on otway-rees, denning-sacco, kerberos and blanchet,
where the first failing goal run returns many shapes. These are references for the OCaml
port, which must reproduce them exactly (E2).

## Replay check: a defect in reference/python/cpsa/cpsa_oracle.py

`survives(x, M)` reads the shape x as surviving M iff CPSA's label-0 skeleton is
`(realized)`. When M contains `(uniq v)` and x originates v on two strands, CPSA does not
reject the input. It either prints label 0 as `(realized) (preskeleton)` with
`(comment "Not a skeleton")` and then collapses the two strands into a different skeleton,
or prints `(realized) (dead)` with `(comment "Input cannot be made into a skeleton--nothing
to do")`. Both are read as "x survives", so `uniq v` is left out of stops(x), the
computed stopping set is too small, and the clause added to H is not a genuine conflict.

On `otway-rees-neq` this makes Algorithm 1 return **false** where the exhaustive answer is
{{non(ltk a s), non(ltk b s), uniq(nb)}}. The corrected check (`../selection/oracle_fixed.py`,
a subclass overriding only `survives`: label 0 must be realized and carry neither
`(preskeleton)` nor `(dead)`) returns the right answer. The corrected check also fires on
otway-rees, neuman-stubblebine, blanchet and blanchet-fixed, changing individual per-shape
stopping sets but not H, W or any call count, because the loop keeps the smallest stopping
set per oracle call and that one was correct. On the existing rows (PKINIT, Yahalom) it
never fires, so the paper's reported numbers are unaffected. `reference/python/cpsa/notes_stops.md` already states
the intended semantics ("if CPSA rejects the skeleton as ill-formed ... x does not
survive"); the implementation assumed rejection would appear on stderr. The OCaml `Cpsa`
driver should implement the corrected check. The defect also bears on the paper's sentence
that every attack either oracle reports yields a genuine stopping set: that holds for the
corrected check only.

## Goals (verbatim) and U per row

### pkinit-flawed

- source: tst/pkinit.scm (defprotocol pkinit), renamed pkinit-flawed; otherwise identical to the shipped text; re-derived from artifact/pkinit_mintrust.py
- goal: written (existing row): client authenticates the server, agreement with an auth strand on (c, as, k)
- note: role declarations uniq-orig n1 n2 [client] and uniq-orig k ak [auth] stay in sigma
- U: `non_as` = `(non (privk as))`; `non_c` = `(non (privk c))`

```scheme
(defgoal pkinit-flawed
  (forall ((c as name) (k skey) (z strd))
    (implies
      (and (p "client" z 2)
           (p "client" "c" z c)
           (p "client" "as" z as)
           (p "client" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "auth" z-0 1) (p "auth" "as" z-0 as)
             (p "auth" "k" z-0 k) (p "auth" "c" z-0 c))))))
```

### pkinit-fix2

- source: not shipped in tst/: adopted fix (server signs a hash of the client request), as in artifact/pkinit_mintrust.py; re-derived from artifact/pkinit_mintrust.py
- goal: written (existing row): client authenticates the server, agreement with an auth strand on (c, as, k)
- note: role declarations uniq-orig n1 n2 [client] and uniq-orig k ak [auth] stay in sigma
- U: `non_as` = `(non (privk as))`; `non_c` = `(non (privk c))`

```scheme
(defgoal pkinit-fix2
  (forall ((c as name) (k skey) (z strd))
    (implies
      (and (p "client" z 2)
           (p "client" "c" z c)
           (p "client" "as" z as)
           (p "client" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "auth" z-0 1) (p "auth" "as" z-0 as)
             (p "auth" "k" z-0 k) (p "auth" "c" z-0 c))))))
```

### yahalom

- source: tst/yahalom.scm (defprotocol yahalom), protocol text unchanged; re-derived from artifact/cpsa/protocols.py
- goal: written (existing row): responder agreement with the initiator on (a, b, c, k)
- U: `non_ltk_ac` = `(non (ltk a c))`; `non_ltk_bc` = `(non (ltk b c))`; `uniq_na` = `(uniq n-a)`; `uniq_nb` = `(uniq n-b)`

```scheme
(defgoal yahalom
  (forall ((a b c name) (n-a n-b text) (k skey) (z strd))
    (implies
      (and (p "resp" z 4) (p "resp" "a" z a) (p "resp" "b" z b) (p "resp" "c" z c)
           (p "resp" "n-a" z n-a) (p "resp" "n-b" z n-b) (p "resp" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "c" z-0 c) (p "init" "k" z-0 k))))))
```

### otway-rees

- source: tst/or.scm (defprotocol or), protocol text unchanged
- goal: written: responder agreement with the initiator on (a, b, s, m)
- U: `non_ltk_as` = `(non (ltk a s))`; `non_ltk_bs` = `(non (ltk b s))`; `uniq_m` = `(uniq m)`; `uniq_nb` = `(uniq nb)`

```scheme
(defgoal or
  (forall ((a b s name) (m nb text) (k skey) (z strd))
    (implies
      (and (p "resp" z 4) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "s" z s) (p "resp" "m" z m) (p "resp" "nb" z nb)
           (p "resp" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 1) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "s" z-0 s) (p "init" "m" z-0 m))))))
```

### denning-sacco

- source: tst/denning-sacco.scm (defprotocol denning-sacco), protocol text unchanged
- goal: written: responder agreement with the initiator on (a, b, k)
- U: `non_privk_a` = `(non (privk a))`; `non_privk_b` = `(non (privk b))`; `non_privk_ks` = `(non (privk ks))`; `uniq_k` = `(uniq k)`; `uniq_ta` = `(uniq ta)`

```scheme
(defgoal denning-sacco
  (forall ((a b ks name) (k skey) (ta text) (z strd))
    (implies
      (and (p "resp" z 1) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "ks" z ks) (p "resp" "k" z k) (p "resp" "ta" z ta)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "k" z-0 k))))))
```

### kerberos

- source: tst/kerberos.scm (defprotocol kerberos), protocol text unchanged
- goal: written: initiator agreement with the responder on (a, b, k)
- note: l is the ticket lifetime, not a nonce or timestamp: no uniq atom (first pass had one, see selection/candidates/kerberos-sortrule.scm)
- U: `non_ltk_aks` = `(non (ltk a ks))`; `non_ltk_bks` = `(non (ltk b ks))`; `uniq_t` = `(uniq t)`; `uniq_tp` = `(uniq t-prime)`

```scheme
(defgoal kerberos
  (forall ((a b ks name) (t t-prime l text) (k skey) (z strd))
    (implies
      (and (p "init" z 4) (p "init" "a" z a) (p "init" "b" z b)
           (p "init" "ks" z ks) (p "init" "t" z t) (p "init" "t-prime" z t-prime)
           (p "init" "l" z l) (p "init" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "resp" z-0 2) (p "resp" "a" z-0 a) (p "resp" "b" z-0 b)
             (p "resp" "k" z-0 k))))))
```

### neuman-stubblebine

- source: tst/neuman-stubblebine.scm (defprotocol neuman-stubblebine), protocol text unchanged
- goal: written: responder agreement with the initiator on (a, b, k)
- U: `non_ltk_aks` = `(non (ltk a ks))`; `non_ltk_bks` = `(non (ltk b ks))`; `uniq_ra` = `(uniq ra)`; `uniq_rb` = `(uniq rb)`; `uniq_tb` = `(uniq tb)`

```scheme
(defgoal neuman-stubblebine
  (forall ((a b ks name) (ra rb tb text) (k skey) (z strd))
    (implies
      (and (p "resp" z 3) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "ks" z ks) (p "resp" "ra" z ra) (p "resp" "rb" z rb)
           (p "resp" "tb" z tb) (p "resp" "k" z k)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "k" z-0 k))))))
```

### isoreject

- source: tst/isoreject.scm (defprotocol isoreject), protocol text unchanged
- goal: written: responder agreement with the initiator on (a, b, nb)
- U: `non_privk_a` = `(non (privk a))`; `non_privk_b` = `(non (privk b))`; `uniq_na` = `(uniq na)`; `uniq_nc` = `(uniq nc)`

```scheme
(defgoal isoreject
  (forall ((a b name) (na nb nc text) (z strd))
    (implies
      (and (p "resp" z 3) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "na" z na) (p "resp" "nb" z nb) (p "resp" "nc" z nc)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "nb" z-0 nb))))))
```

### isofix

- source: tst/isoreject-corrected.scm (defprotocol isofix), protocol text unchanged
- goal: written: responder agreement with the initiator on (a, b, nb) (same goal as isoreject)
- U: `non_privk_a` = `(non (privk a))`; `non_privk_b` = `(non (privk b))`; `uniq_na` = `(uniq na)`; `uniq_nc` = `(uniq nc)`

```scheme
(defgoal isofix
  (forall ((a b name) (na nb nc text) (z strd))
    (implies
      (and (p "resp" z 3) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "na" z na) (p "resp" "nb" z nb) (p "resp" "nc" z nc)
           @TRUST@)
      (exists ((z-0 strd))
        (and (p "init" z-0 3) (p "init" "a" z-0 a) (p "init" "b" z-0 b)
             (p "init" "nb" z-0 nb))))))
```

### blanchet

- source: tst/blanchet.scm (defprotocol blanchet), protocol text unchanged (comments dropped)
- goal: written: secrecy of d from the responder's point of view (the shipped skeleton 4 for this protocol, resp + deflistener d, as a goal)
- note: secondary candidate (not on the preferred list); admitted for the secrecy goal class, see MANIFEST.md
- U: `non_privk_a` = `(non (privk a))`; `non_privk_b` = `(non (privk b))`; `uniq_s` = `(uniq s)`; `uniq_d` = `(uniq d)`

```scheme
(defgoal blanchet
  (forall ((a b name) (s skey) (d data) (z z-0 strd))
    (implies
      (and (p "resp" z 2) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "s" z s) (p "resp" "d" z d)
           (p "" z-0 1) (p "" "x" z-0 d)
           @TRUST@)
      (false))))
```

### blanchet-fixed

- source: tst/blanchet.scm (defprotocol blanchet-fixed), protocol text unchanged (comments dropped)
- goal: written: secrecy of d from the responder's point of view (the shipped skeleton 4 for this protocol, resp + deflistener d, as a goal)
- note: secondary candidate (not on the preferred list); admitted for the secrecy goal class, see MANIFEST.md
- U: `non_privk_a` = `(non (privk a))`; `non_privk_b` = `(non (privk b))`; `uniq_s` = `(uniq s)`; `uniq_d` = `(uniq d)`

```scheme
(defgoal blanchet-fixed
  (forall ((a b name) (s skey) (d data) (z z-0 strd))
    (implies
      (and (p "resp" z 2) (p "resp" "a" z a) (p "resp" "b" z b)
           (p "resp" "s" z s) (p "resp" "d" z d)
           (p "" z-0 1) (p "" "x" z-0 d)
           @TRUST@)
      (false))))
```

## Reproduce

```
cd cpsa/selection
python3 evaluate.py                       # all rows in ../protocols
python3 evaluate.py woolam wide-mouth-frog iso-unilateral kerberos-sortrule \
        kerberos-key otway-rees-neq       # candidates and diagnostics
python3 table.py rows; python3 table.py cands; python3 table.py goals
```

Wide-Mouthed Frog takes about 4 minutes (four 60 s timeouts).

## Author decisions (2026-10-04)

- Otway-Rees: both rows are reported, the mechanical one (`otway-rees`, W = false via the
  a = b run) and `otway-rees-neq` (a != b in the situation). Both templates are in this
  directory.
- Kerberos: the row uses the key-agreement goal (`kerberos-key`). The name-agreement
  template moved to `../selection/candidates/kerberos-names.scm`; the paper mentions in one
  sentence that name agreement fails in this simplified model because the tickets are
  symmetric.
