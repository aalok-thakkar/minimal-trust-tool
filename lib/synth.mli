(** Synthetic instances for the scalability study (experiment E3; Python counterpart
    [scale.py]).

    A hypergraph [h] over generators [0..n-1] stands for the protocol of the reduction
    in Appendix A of the paper: generator [i] is [Non(k_i)] and each edge is the
    stopping set of the one minimal attack on a component. After minimalisation [h] is
    a clutter, so [attacks chi = h] and [weakest chi = Clutter.blocker h].

    Generator [i] is the atom [atom i = "Non(k_07)"] (two-digit index), so the canonical
    order of {!Aset} on these atoms agrees with numeric order. Every family returned
    here is a clutter in canonical order ({!Clutter.sort}). Randomness comes only from
    the explicit [Random.State.t] passed in. *)

val atom : int -> Aset.atom
(** [atom i = "Non(k_ii)"], [0 <= i < 100]. *)

val index : Aset.atom -> int
(** Inverse of {!atom}. Raises [Invalid_argument] on other strings. *)

val universe : int -> Aset.t
(** [{atom 0, ..., atom (n-1)}]. *)

val of_indices : int list list -> Clutter.family
(** Edges given by generator indices, minimalised. *)

val random : Random.State.t -> n:int -> m:int -> Clutter.family
(** [m] edges over [n] generators, each of size uniform in [1..min 3 n] and drawn
    uniformly among sets of that size; the result is minimalised, so it may have
    fewer than [m] edges. *)

val random_state : family:string -> n:int -> m:int -> seed:int -> Random.State.t
(** The state used for instance [(family, n, m, seed)]:
    [Random.State.make [|2026; n; m; seed; c_1; ...; c_l|]] where [c_i] are the
    character codes of [family]. *)

val disjoint_pairs : int -> Clutter.family
(** [{0,1}, {2,3}, ...]: [n/2] edges; its blocker has [2^(n/2)] members. *)

val dual_pairs : int -> Clutter.family
(** [blocker (disjoint_pairs n)]: [2^(n/2)] edges of size [n/2]; blocker has [n/2]. *)

val threshold : s:int -> k:int -> Clutter.family
(** All [k]-subsets of [{0..s-1}] ([1 <= k <= s]). Its blocker is the family of all
    [(s-k+1)]-subsets. *)

val achieves : Clutter.family -> Aset.t -> bool
(** [achieves h t] iff [t] meets every edge of [h]. *)

val hypergraph_oracle : Clutter.family -> Aset.t -> Loop.answer
(** The reduction semantics: [t] achieves iff it meets every edge; otherwise the
    witness is the first edge of [h] (in the order given; canonical for families from
    this module) that [t] misses. For a clutter [h] every witness is a minimal attack,
    the hypothesis of the call bound of Theorem thm:cost. *)

val padded_oracle :
  ?extra:int -> Random.State.t -> u:Aset.t -> Clutter.family -> Aset.t -> Loop.answer
(** As {!hypergraph_oracle}, but a failing witness is the missed edge [e] plus extra
    atoms of [u \ (t + e)], drawn from the given state at each call: [min k |u \ (t +
    e)|] of them uniformly with [~extra:k], otherwise each independently with
    probability 1/2. The witness is a genuine stopping set (it contains an attack and
    misses [t]) but in general not a minimal one. *)
