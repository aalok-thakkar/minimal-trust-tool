(** Bounded strand-space search with a Dolev-Yao network intruder (port of the engines
    of [analyzer.py], [cr.py], [channels.py] and [composition.py]).

    {2 Model}

    A protocol instance is a fixed pool of strands. A strand is a sequence of sends and
    receives over message templates with variables; variables are local to their strand
    and are bound by the first receive that mentions them, or in advance by a scenario.
    The intruder is the network:
    - an honest send of [m] on channel [c] records [(c, m)] as sent and, unless [c] is
      confidential in the current world, adds [m] to the intruder's knowledge;
    - an honest receive is an instance of the step's template, with its unbound
      variables taken from a finite list of atoms ({!model.values}), and is possible iff
      [(c, m)] was sent on [c] (delivery), or [c] is not authentic and [m] is derivable
      from the intruder's knowledge (injection), or, with {!model.hijack}, [c] is not
      authentic and [m] was sent on some channel (re-ascription without learning).
    A step without a channel is on an unrestricted channel. Derivability is the
    analysis/synthesis closure, which agrees with {!Dy.derivable} (tested).

    The trust [T] enters only through {!model.world}: initial knowledge, authentic and
    confidential channels, and the scenarios (choices fixed in advance, such as whether
    the test nonce is fresh or stale). Bounded knows nothing else about atoms.

    {2 Runs and stopping sets}

    A run is a scenario name and a sequence of events. It {e replays} under [T] iff its
    scenario is one of [(world T).scenarios] and every event is the next step of its
    strand, executable in [world T]. For a run [x] found under [T],
    [stops x = {a in U \ T : x does not replay under T + {a}}] (Definition 3 by replay,
    one atom at a time, as [analyzer._stops] and [cr.trace_stops]).

    {2 Search}

    Each scenario of [world T] is searched in list order, depth first with an explicit
    LIFO stack. Successors are pushed in strand order and, for a receive, in the order of
    the assignments of its free variables (variables sorted by name, the first one
    outermost, values in {!model.values} order), so the highest strand and the last value
    are expanded first; this is the order of the Python reference. A state is checked
    against the visited table when popped; a popped state violating the goal is an
    attack state and is not extended. The visited key is (positions, bindings, goal
    flags), plus, if [key_stops], the set of atoms of [U \ T] whose world already breaks
    the run so far; the intruder's knowledge and the sent set are functions of the
    positions and bindings, so they need not be in the key. *)

type chan = string * string
(** [(sender, receiver)] as the role sees them. *)

type tmpl =
  | T of Term.t  (** a ground term *)
  | V of string  (** a variable of the strand *)
  | P of tmpl * tmpl
  | E of tmpl * tmpl  (** [E (key, msg)] *)
  | S of tmpl * tmpl  (** [S (key, msg)] *)

type dir = Send | Recv
type step = { dir : dir; chan : chan option; msg : tmpl }
type strand = { label : string; steps : step list }

type scenario = { sname : string; fixed : (int * string * Term.t) list }
(** A scenario pre-binds variables: [(strand index, variable, value)]. *)

type world = {
  k0 : Term.t list;  (** the intruder's initial knowledge *)
  auth : chan list;  (** channels on which the intruder cannot inject or re-ascribe *)
  conf : chan list;  (** channels whose messages the intruder does not learn *)
  scenarios : scenario list;  (** searched in this order *)
}

type view = {
  pos : int array;  (** number of events done per strand *)
  value : int -> string -> Term.t option;  (** binding of a strand's variable *)
  flags : int;  (** goal flags (see {!goal}) *)
}

type event = { edir : dir; strand : int; step : int; echan : chan option; msg : Term.t }

type goal = {
  update : view -> event -> int;
      (** New goal flags after an event; the view is the state after the event, with the
          flags before it. Flags record history the goal needs (e.g. "the prover answered
          after the challenge was sent"); they are part of the visited key. *)
  violated : view -> bool;  (** the state is an attack state *)
}

type model = {
  strands : strand array;
  values : Term.t list;  (** the atoms a received variable may take, in search order *)
  world : Aset.t -> world;
  goal : goal;
  test : int list;  (** strands {!prune} never shortens *)
  hijack : bool;
}

type run = { scenario : string; events : event list  (** chronological *) }

type mode =
  | As_found  (** the first attack state of the search, its run as found *)
  | Pruned  (** the first attack, pruned to a minimal run ({!prune}) *)
  | Least
      (** every reachable attack state (stopping early on an empty stopping set); a run
          whose stopping set is least in {!Aset.compare_size_lex}, hence subset-minimal *)

type outcome = Achieves | Attack of { run : run; stops : Aset.t }

type result = {
  outcome : outcome;
  states : int;  (** distinct states expanded, over all scenarios *)
  attack_states : int;  (** distinct attack states reached *)
  nonprincipal : int;
      (** with [check_lattice], [Least] mode: attack states whose run has several
          {!clauses} (a pair of atoms removing a run neither removes alone) *)
}

exception Timeout

val search :
  ?deadline:float ->
  ?key_stops:bool ->
  ?check_lattice:bool ->
  ?reduce:bool ->
  model ->
  u:Aset.t ->
  mode ->
  Aset.t ->
  result
(** [search model ~u mode t] decides the goal under trust [t] in the bounded pool. The
    returned stopping set is computed by replay ({!stops}) on the returned run. [Least]
    always keys on stopping sets; for the other modes [key_stops] (default [true]) only
    changes which states are merged (the Python NSPK/NSL engine keys without them, the
    challenge-response engine with them). Raises [Timeout] once [Unix.gettimeofday ()]
    exceeds [deadline] (checked every 1024 states).

    [~reduce:true] (default [false]) shrinks the space without changing the verdict or
    the subset-minimal stopping sets (it changes which run is found first, so call
    counts may differ):
    - {e block coalescing}: a strand's receives are executed together with its next
      send, as one transition (trailing receives as one transition). A run can be
      rearranged so that every receive happens just before the next event of its
      strand, or at the end: knowledge and the sent set only grow, so the receives stay
      possible, in every world, and the stopping set can only shrink; final positions
      and bindings are unchanged;
    - {e symmetry}: non-test strands with identical steps (copies of a role without
      fresh values of their own) are interchangeable, so the visited key holds the
      sorted list of their local states.
    Requirements on the goal: [update] must not depend on when a receive of another
    strand happens beyond the positions reached by sends (true of every goal in
    {!Protocols}: flags change only at sends, conditioned on a strand having passed a
    send), [violated] must be evaluated on positions and bindings only, and both must
    treat the members of a symmetry group alike. *)

val replays : model -> Aset.t -> run -> bool
val is_attack : model -> Aset.t -> run -> bool
(** The run replays under the trust and its final state violates the goal. *)

val stops : model -> u:Aset.t -> Aset.t -> run -> Aset.t

val prune : model -> u:Aset.t -> Aset.t -> run -> run
(** [cr.prune]: repeatedly, for each non-test strand with events in the run (in index
    order, the set taken once per round), drop its last event if the result still
    replays, is still an attack, and its stopping set is a subset of the current one;
    until a round changes nothing. *)

val clauses : model -> u:Aset.t -> Aset.t -> run -> Aset.t list
(** [channels.clauses]: with [U' = U \ T] and [D = {S <= U' : run replays under T + S}],
    the sets [U' \ M] for the maximal [M] in [D], canonical order. One clause, equal to
    {!stops}, iff [D] is principal (separable stopping, A6). Requires [|U'| <= 16]. *)

val derivable : Term.t list -> Term.t -> bool
(** Intruder derivability via analysis/synthesis; equal to {!Dy.derivable}. *)

type counter = {
  mutable calls : int;
  mutable states : int;  (** summed over calls *)
  mutable max_states : int;  (** largest single call *)
  mutable time : float;
  mutable nonprincipal : int;
      (** witnesses whose {!clauses} has several members (checked when [|U \ T| <= 12]) *)
}

val counter : unit -> counter

val oracle :
  ?deadline:float ->
  ?key_stops:bool ->
  ?reduce:bool ->
  ?counter:counter ->
  model ->
  u:Aset.t ->
  mode ->
  Aset.t ->
  Loop.answer
(** {!search} as an oracle for {!Loop.weakest}; the witness description is the run. *)

val pp_event : Format.formatter -> event -> unit
val pp_run : model -> Format.formatter -> run -> unit
