(** Dolev-Yao derivability (port of [dy.py]).

    Rules, applied to a fixpoint:
    - decomposition: from [Pair (a, b)] get [a] and [b]; from [Sig (k, m)] get [m];
      from [Enc (k, m)] and [inverse k] get [m];
    - composition: from [a], [b] get [Pair (a, b)]; from [k], [m] get [Enc (k, m)]
      and [Sig (k, m)].

    Composition is restricted to a finite universe: the subterms of the knowledge and
    the target, plus the inverse of every such subterm. This keeps the closure finite
    and is complete for deciding [derivable] (locality): a derivation can be normalised
    so that no composed term is later decomposed (projecting a composed pair, opening a
    composed signature or decrypting a term one encrypted oneself returns a term already
    known). In a normal derivation every term obtained by decomposition is a subterm of
    the knowledge, and every composed term is either a subterm of the target or a key
    used for decryption. A decryption key is [inverse k] for a key [k] that is a subterm
    of the knowledge; for a compound [k] this is [k] itself (compound keys are
    symmetric), and a name cannot be composed. So all terms of a normal derivation lie
    in the universe. Semantics are identical to the Python reference. *)

val universe : Term.t list -> Term.Set.t
(** Subterms of the given terms, closed under adding [inverse t] for each of them. *)

val closure : Term.Set.t -> Term.Set.t -> Term.Set.t
(** [closure known univ]: the deductive closure of [known], with composition producing
    only members of [univ]. Decomposition is unrestricted (it only produces subterms
    of [known]). *)

val derivable : Term.t list -> Term.t -> bool
(** [derivable known target] iff [target] is in
    [closure known (universe (target :: known))]. *)
