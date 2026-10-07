(** Algorithm 1 (the counterexample-guided loop) and the baselines.

    An oracle decides achievement for a trust [t] (a subset of the generators [u]). On
    failure it returns a witness: the stopping set [stops(x)] of a counterexample run
    [x], i.e. the generators of [u] whose assumption rules [x] out, and a free-form
    description of [x]. *)

type witness = { stops : Aset.t; descr : string }
type answer = Achieves | Fails of witness

type stats = {
  distinct : int;  (** oracle calls made (distinct trusts); Theorem thm:cost counts these *)
  queries : int;
      (** candidate evaluations in the main loop, memo hits included: the calls the
          unmemoised loop would make (Python [stats['total']]); shrink queries excluded *)
  shrink_calls : int;  (** oracle calls made while shrinking witnesses (part of [distinct]) *)
  oracle_time : float;  (** seconds spent inside the oracle *)
  blocker_time : float;  (** seconds spent computing blockers *)
  iterations : int;  (** blocker computations: failures + 1 *)
}

exception Unsound_witness of string
(** Raised when a witness violates the oracle contract: its stopping set is not a
    subset of [u], meets the trust it fails, contains a member of the current [H] (main
    loop), or is not inside [S \ {a}] (shrink). The message names the trust and the
    witness. *)

val weakest :
  ?shrink:bool -> u:Aset.t -> (Aset.t -> answer) -> Aset.t list * Aset.t list * stats
(** [weakest ~u oracle = (w, h, stats)]. Algorithm 1 with a memo table keyed on the
    trust: each distinct trust is sent to the oracle at most once. Candidates are
    [Clutter.blocker h] in canonical order (size, then lexicographic); the first failing
    candidate adds its stopping set to [h], which is then minimalised. Returns when every
    candidate achieves; [w = Clutter.blocker h] is the weakest trust and, for a sound and
    complete oracle, [h] is the clutter of minimal attacks (Theorem thm:correctness).
    Both are in canonical order. An empty stopping set gives [h = [{}]] and [w = []]
    (the answer [false]: no trust suffices).

    [~shrink:true] minimalises each main-loop witness [s] before it enters [h]
    (Theorem thm:cost): with [S := s], for each [a] of [s] in order and still in [S],
    query [u \ (S \ {a})]; if it fails with stopping set [s'], then [S := s'];
    otherwise [a] stays. Each element is tested once, and [S] is always a genuine
    stopping set. *)

val brute_force : u:Aset.t -> (Aset.t -> bool) -> Aset.t list
(** Baseline B1: evaluate the predicate on all [2^|u|] trusts and return the minimal
    sufficient ones in canonical order. Requires [|u| <= 30]. Makes exactly
    [2^|u|] calls. The predicate must be monotone for the answer to be [W]. *)

type levelwise_result = {
  found : Aset.t list;  (** minimal sufficient trusts found, canonical order *)
  calls : int;  (** predicate calls made *)
  complete : bool;  (** false iff the budget stopped the search *)
}

val levelwise : ?budget:int -> u:Aset.t -> (Aset.t -> bool) -> levelwise_result
(** Baseline B2: enumerate trusts by size (each size in lexicographic order), skipping
    supersets of sufficient trusts already found, and call the predicate on the rest.
    For a monotone predicate, [found] is exactly [W] when [complete]. Stops before the
    call that would exceed [budget] (default: unlimited). *)

val greedy_rgl : u:Aset.t -> (Aset.t -> bool) -> Aset.t option * int
(** Baseline B3, the conjunct-dropping heuristic of Rowe, Guttman and Liskov: check [u];
    if it is insufficient return [(None, 1)]. Otherwise start from [u] and, for each atom
    in increasing order, drop it if the trust stays sufficient. Returns one trust and the
    call count [1 + |u|]. For a monotone predicate the trust is a member of [W]. *)

val pp_stats : Format.formatter -> stats -> unit
