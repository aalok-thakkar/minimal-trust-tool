(** Clutters (Sperner families), minimal transversals and the blocker.

    A family is a list of trusts. Every function returning a family returns it without
    duplicates and in canonical order: by size, then lexicographic
    ({!Aset.compare_size_lex}). For a clutter [h], [blocker (blocker h) = h]
    (Edmonds-Fulkerson; Isbell), and [weakest chi = blocker (attacks chi)]
    (Proposition prop:hitting of the paper). *)

type family = Aset.t list

val sort : family -> family
(** Remove duplicates and put in canonical order. *)

val minimalize : family -> family
(** The inclusion-minimal members, in canonical order. Cost: one sort plus, for each
    member [s], work proportional to the number of incidences between the atoms of [s]
    and the kept sets of strictly smaller size (an inverted index with counters); no
    pairwise subset scan, and nothing beyond the sort for a family of equal-size sets. *)

val hits : Aset.t -> Aset.t -> bool
(** [hits t e] iff [t] and [e] meet. *)

val is_transversal : Aset.t -> family -> bool
(** [is_transversal t h] iff [t] meets every member of [h]. Every set is a transversal
    of [[]]; no set is a transversal of a family containing the empty set. *)

val blocker : family -> family
(** The clutter of minimal transversals of [h] (Berge's incremental algorithm on
    [minimalize h]). [blocker [] = [empty]]; [blocker h = []] if [h] contains the empty
    set. *)

val equal_family : family -> family -> bool
(** Equality as sets of sets (order and duplicates ignored). *)

val pp_family : Format.formatter -> family -> unit
(** Prints [[{a}, {b, c}]] in canonical order. *)
