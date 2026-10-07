(** Dolev-Yao terms (port of [dy.py]).

    Atoms are names: principal names, nonces, constants and key handles. Key handles
    follow a naming convention that {!inverse} knows: [pk_X] and [sk_X] are inverse
    (public / private), every other key, including a compound key, is self-inverse
    (symmetric). *)

type t =
  | Name of string  (** an atom *)
  | Pair of t * t  (** pairing *)
  | Enc of t * t  (** [Enc (key, msg)]: needs [inverse key] to open *)
  | Sig of t * t  (** [Sig (key, msg)]: exposes [msg]; producing it needs [key] *)

val name : string -> t
val pair : t -> t -> t
val enc : t -> t -> t
val sign : t -> t -> t
(** [sign key msg = Sig (key, msg)] ([sig] is an OCaml keyword). *)

val inverse : t -> t
(** [pk_X <-> sk_X]; everything else is its own inverse. *)

val compare : t -> t -> int
val equal : t -> t -> bool

module Set : Set.S with type elt = t

val subterms : t -> Set.t
(** All subterms, including the term itself. Keys are subterms. *)

val pp : Format.formatter -> t -> unit
val to_string : t -> string
