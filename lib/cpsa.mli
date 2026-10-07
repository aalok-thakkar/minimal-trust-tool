(** CPSA 4 as the achievement oracle of Algorithm 1 (paper Section 8, "Computing
    stops(x) from a backend"; Appendix "The CPSA Oracle").

    A protocol row is a template file (format: [cpsa/protocols/README.md]): header lines
    [;; @name], [;; @source], [;; @goal], [;; @note], ..., one [;; @U <id> <fact>] line per
    generator, the protocol text, and one [defgoal] holding the placeholder [@TRUST@].
    Generators are the atom ids of the [@U] lines (Aset atoms); a trust [T] becomes the
    facts of its atoms, in increasing id order, in place of the placeholder.

    Goal run at [T]: CPSA must end with its search exhausted ([Nothing left to do], exit
    status 0, empty stderr, no [(aborted)] skeleton, no step-limit / strand-bound /
    aborting message); anything else raises {!Cpsa_error} and is never read as a verdict.
    [T] achieves iff no shape carries [(satisfies (no ...))].

    Replay ("x survives M"): the failing shape is printed back as a [defskeleton] with the
    atoms of [M], instantiated by the variable bindings of its [(satisfies (no ...))]
    verdict, added to its [non-orig] / [uniq-orig] lists. x survives iff CPSA's label-0
    skeleton is [(realized)] and carries neither [(preskeleton)] nor [(dead)] (the
    corrected check of [cpsa/selection/oracle_fixed.py]); output on stderr means CPSA
    rejected the input, and x does not survive. *)

(** {1 S-expressions} *)

module Sexp : sig
  type t = Atom of string | List of t list
  (** Atoms are raw tokens: a string literal keeps its quotes. *)

  val parse_all : string -> t list
  (** All top-level forms. [;] comments are skipped. Raises [Failure] on unbalanced
      input. *)

  val to_string : t -> string
  (** Single-line printing: atoms as read, lists as [(x y ...)]. *)

  val field : t -> string -> t list
  (** [field form key]: the sub-forms of the list [form] whose head is the atom [key]. *)
end

(** {1 Templates} *)

type template = {
  path : string;
  name : string;  (** [@name] *)
  meta : (string * string) list;  (** all header lines other than [@U], in file order *)
  u : (string * string) list;  (** [(atom id, fact text)], in file order *)
  proto : string;  (** everything before [(defgoal], header lines removed *)
  goal_text : string;  (** the [defgoal], with the placeholder *)
}

val placeholder : string
(** ["@TRUST@"] *)

val load_template : string -> template
(** Raises [Failure] if [@name] is missing, there is no [(defgoal], or the placeholder
    does not occur exactly once, in the goal. *)

val templates_in : string -> string list
(** The [*.scm] files of a directory, sorted by file name. *)

val universe : template -> Aset.t

val fact : template -> Aset.atom -> string
(** Raises [Not_found] for an atom outside [u]. *)

val goal_source : template -> Aset.t -> string
(** CPSA input for the goal at trust [T]: [(herald "<name> trust")], the protocol text
    and the goal with the facts of [T] (increasing atom id) in place of the
    placeholder. *)

(** {1 Running CPSA} *)

exception Cpsa_error of string
(** A CPSA run that is not a complete search, or that could not be run. *)

val binary : unit -> string option
(** [$CPSA4] if set, else [cpsa4] on [PATH], else [~/.local/bin/cpsa4]; [None] if the
    chosen file is not executable. *)

type run = {
  stdout : string;
  stderr : string;
  status : Unix.process_status option;  (** [None] on timeout (the process is killed) *)
  time : float;  (** wall seconds, process start to exit *)
}

val run_cpsa : ?timeout:float -> string -> run
(** Runs CPSA (no options) on the given input text. Default timeout 600 s. Raises
    {!Cpsa_error} if no binary is found. *)

val version : unit -> string
(** First line of [cpsa4 --version] (stdout or stderr). *)

(** {1 Reading goal runs} *)

type failing = { shape : Sexp.t; binding : Sexp.t  (** the [(no ...)] form *) }

type goal_result = {
  incomplete : string option;  (** [Some reason] iff the run is not a complete search *)
  skeletons : int;
  shapes : int;
  failing : failing list;  (** one per [(satisfies (no ...))], in output order *)
}

val read_goal_output : run -> goal_result

val achieves_of : goal_result -> bool
(** [failing = []]. Meaningful only when [incomplete = None]. *)

(** {1 Replay} *)

val replay_source : template -> failing -> Aset.atom list -> string
(** CPSA input for the replay of the shape with the given atoms, in the given order
    (same construction as [cpsa_oracle.CPSAOracle.survives]). *)

type replay_verdict =
  | Realized
  | Unrealized
  | Rejected of string  (** [preskeleton], [dead], or [ill-formed: <stderr>] *)

val read_replay_output : run -> replay_verdict
val survives : replay_verdict -> bool

(** {1 The oracle} *)

type stats = {
  mutable goal_runs : int;
  mutable replay_runs : int;
  mutable goal_time : float;  (** CPSA wall seconds in goal runs *)
  mutable replay_time : float;
  mutable rejected : int;  (** replays read as not surviving because of the correction *)
  mutable ill_formed : int;  (** replays with stderr output *)
  mutable log : string list;  (** newest first *)
}

val new_stats : unit -> stats
val cpsa_time : stats -> float

val goal_run : ?timeout:float -> ?stats:stats -> template -> Aset.t -> goal_result
(** One goal run. Raises {!Cpsa_error} if the run is incomplete. *)

val verdict : ?timeout:float -> ?stats:stats -> template -> Aset.t -> bool
(** Achievement at [T] (one goal run, no replay). *)

val stops :
  ?timeout:float -> ?stats:stats -> template -> Aset.t -> failing -> Aset.t * string
(** The accumulation recipe: [M := {}]; for each [a] of [U \ T] in increasing id order,
    if the shape survives [M ∪ {a}] then [M := M ∪ {a}]. Returns the clause
    [U \ (T ∪ M)] and a log line. One replay run per atom of [U \ T]. *)

val oracle : ?timeout:float -> ?stats:stats -> template -> Aset.t -> Loop.answer
(** One goal run; on failure, [stops] for every failing shape and the first clause in
    {!Aset.compare_size_lex} order (a ⊆-minimal one). *)
