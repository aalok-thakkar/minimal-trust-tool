# The bounded analyser: pool, intruder, term bound, search order

Applies to the four analyser rows of Table 2 (signed CR, two-key variant, Needham-Schroeder,
Lowe's fix). Code: cr.py (first two rows), analyzer.py (last two), dy.py (derivability).

## Common to all rows

* Intruder. Dolev-Yao, acting as the network. Every honest send is added to the intruder's
  knowledge K. Every honest receive is an instance of the role's message template whose
  variables are bound to atoms from a fixed pool, accepted only if the instance is derivable
  from K. Derivability (dy.closure) closes K under projection, pairing, decryption with the
  inverse key, encryption, signing, and reading a signed message, with composition
  restricted to the subterms of K and the target plus their inverse keys. For this term
  algebra that restriction is the standard locality property, so the check is exact for a
  given target.
* Term bound. Variables range over atoms only (no compound substitutions, so no type-flaw
  runs). Received messages therefore have the fixed depth of the role templates: depth 3
  for NSPK/NSL and the signed CR, depth 4 for the two-key variant.
* Trust atoms. Non(k): k is absent from the intruder's initial knowledge. Unq(N) (CR rows
  only): the test nonce originates only at the test strand.
* stops(x). Non(k) is in stops(x) iff k is not assumed and replaying x with k removed from
  the initial knowledge leaves some receive underivable. Unq(N) is in stops(x) iff the test
  nonce in x is the stale nonce of the earlier session.
* Search. Depth-first over interleavings, LIFO stack, states deduplicated. A "pass" means
  the whole bounded state space was explored with no attack. The first attack found is
  returned.

## Signed CR and two-key variant (cr.py)

Strand pool, one instance each (both parties run both roles; A also answers the intruder):

| # | strand | steps |
|---|---|---|
| 0 | Chal(B,A), test | send N_t; recv resp(A,B,N_t) |
| 1 | Prov(A,B) | recv n; send resp(A,B,n) |
| 2 | Prov(B,A) | recv n; send resp(B,A,n) |
| 3 | Chal(A,B) | send N_a; recv resp(B,A,N_a) |
| 4 | Prov(A,I) | recv n; send resp(A,I,n) |

resp(P,Q,n) is sig_{sk_P}(n,P,Q) (signed CR) or {|{|n,P,Q|}_{k1}|}_{k2} (two-key). One
earlier completed honest session of Prov(A,B) on nonce N_old is in the past: N_old and
resp(A,B,N_old) are in the intruder's initial knowledge. Five strands, ten events.

* Initial knowledge: names A, B, I; pk_A, pk_B, pk_I, sk_I; the earlier transcript; every
  key in U whose Non atom is not assumed (sk_A, sk_B, resp. k1, k2).
* Variable pool: {A, B, I, N, N_old, N_a}.
* Freshness: with Unq(N) the test nonce N_t is the fresh atom N; without it, N_t is N or
  N_old (the stale nonce, which the earlier session has already answered).
* Goal (recent agreement for B): when strand 0 completes on N_t, strand 1 has sent
  resp(A,B,N_t) after strand 0 sent N_t.
* Search order: the choice N_t = N is searched first, then N_t = N_old. Within a choice,
  successors are pushed in strand order 0..4 and, for a receive, in pool order, so the
  highest-numbered enabled strand and the last pool value are expanded first. State key:
  (positions, K, binding, keys whose removal already breaks the run, recency flag).
* Witness: the first attack run found is pruned to a minimal run (strand suffixes removed
  while the run stays executable, stays an attack, and its stopping set does not grow) and
  stops is computed on the pruned run. `oracle_for(proto, minimal_run=False)` skips pruning.

## Needham-Schroeder and Lowe's fix (analyzer.py)

Strand pool, one instance each:

| # | strand | steps |
|---|---|---|
| 0 | Init(A,B) | send {Na_0,A}pk_B; recv {Na_0,Nb[,B]}pk_A; send {Nb}pk_B |
| 1 | Init(A,I) | send {Na_1,A}pk_I; recv {Na_1,Nb[,I]}pk_A; send {Nb}pk_I |
| 2 | Resp(B,A), test | recv {Na,A}pk_B; send {Na,Nb_2[,B]}pk_A; recv {Nb_2}pk_B |

(the bracketed name is present in NSL only). Nine events.

* Initial knowledge: names A, B, I; pk_A, pk_B, pk_I, sk_I; sk_A and sk_B unless Non.
* Variable pool: {A, B, I, Na_0, Na_1, Nb_2}, in sorted order.
* Freshness: not in U. Every nonce is a distinct atom (freshness is supplied by the
  situation, following Rowe et al.).
* Goal (non-injective agreement of the responder): when strand 2 completes, strand 0 has
  completed with the same (Na, Nb).
* Search order: successors pushed in strand order 0..2, receives in pool order. State key:
  (positions, K, binding). The first attack found is returned unpruned.

## What each row's verdict means

Every attack the analyser reports is a genuine run of the protocol (a bundle of the
bounded pool is a bundle of the protocol), so every member of the recovered H is a genuine
stopping set and every sufficient trust in the unbounded model must meet it. A "pass" only
says that no attack exists inside the pool. So, for each row:

| row | reported W(chi) | unconditional | relative to the bound |
|---|---|---|---|
| signed CR | {Non(sk_A), Unq(N)} | each of Non(sk_A), Unq(N) is necessary | that the pair suffices |
| two-key | {Non(k1),Unq(N)}, {Non(k2),Unq(N)} | every sufficient trust contains Unq(N) and one of Non(k1), Non(k2) | that each pair suffices |
| Needham-Schroeder | false | yes: Lowe's run has empty stopping set | nothing |
| Lowe's fix | {Non(sk_A)} | Non(sk_A) is necessary | that it suffices |

Only the Needham-Schroeder row is a theorem about the unbounded protocol. The other three
are lower bounds that are theorems, together with sufficiency observed in the stated pool.
Theorem 8's hypothesis (an oracle sound and complete for achievement on the fragment) holds
for these rows only relative to the pool.

## Draft paper text

"Our analyser searches a fixed pool of strands, one instance of each, depth-first with
state deduplication: for the challenge-response rows the test challenger Chal(B,A), the
provers Prov(A,B), Prov(B,A) and Prov(A,I), and a second challenger Chal(A,B), together
with one earlier completed Prov(A,B) session whose transcript the adversary holds; for
Needham-Schroeder and its fix, Init(A,B), Init(A,I) and the test responder Resp(B,A).
Variables are instantiated by atoms only, so received messages have the depth of the role
templates, and intruder derivability is decided exactly within the subterms of its
knowledge and the target. Attacks it reports are genuine runs, so the necessity of each
atom of the reported weakest trust holds without bound; sufficiency is relative to the
pool. The Needham-Schroeder verdict is unconditional; the other three analyser rows are
observations relative to the pool."
