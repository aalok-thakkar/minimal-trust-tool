(** Trust generators and finite sets of them.

    A generator (atom) is a string such as ["Non(sk_A)"] or ["Unq(N)"]. A trust is a
    finite set of generators. [Aset] is [Set.Make (String)] with a canonical total order
    used for every deterministic enumeration in this library. *)

type atom = string

include Set.S with type elt = atom

val compare_size_lex : t -> t -> int
(** Smaller sets first; sets of equal size by lexicographic order of their sorted
    elements. This is the candidate order of Algorithm 1 (same as [cegis._order] in the
    Python reference for identifier-like atoms). [compare_size_lex a b = 0] iff
    [equal a b]. *)

val pp : Format.formatter -> t -> unit
(** Prints [{a, b, c}]; the empty set as [{}]. *)

val to_string : t -> string
