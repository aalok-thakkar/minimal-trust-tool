(** The protocol of the reduction in Appendix A (proof of Theorem thm:cost), with an
    achievement oracle by exhaustive bounded Dolev-Yao search (port of
    [dy_gadget_oracle] in [scale.py]).

    Input: a clutter [h] over the generators [Synth.atom 0 .. Synth.atom (n-1)], edges
    [S_0, ..., S_(m-1)] in the given order. Agents [A], [B_0..B_(m-1)]; symmetric keys
    [k_00..k_(n-1)] (key [k_ii] for generator [Non(k_ii)]); nonces [N_j]; public tags
    [tag_j]. [t_j(N)] encrypts [<N, tag_j>] successively under [k_i] for [i] in [S_j],
    in increasing order. Role [B_j]: send [N_j], receive [t_j(N_j)]. Role [A_j]:
    receive a nonce [N], send [t_j(N)]. The pool has one strand of each role per edge.

    The search explores every interleaving of the pool with the intruder as the
    network: a send adds its message to the intruder knowledge, a reception of a fixed
    message needs {!Dy.derivable}, and [A_j]'s reception binds [N] to any nonce [N_l]
    the intruder can derive. The initial knowledge is the public names plus [k_i] for
    every [i] whose generator is not in the trust. States are identified by strand
    positions and bindings (the knowledge is a function of these). A state violates
    the goal if some [B_j] has completed while [A_j] has not completed with [N = N_j]
    (non-injective agreement of [B_j] with [A] on [N_j]). The witness of a violating
    run is computed by replay, as [analyzer._stops] does: the generators [Non(k_i)]
    outside the trust such that removing [k_i] from the initial knowledge makes some
    reception of the run underivable.

    The search is exponential in the number of edges; it is meant for [m <= 4]. *)

val term : Aset.t -> int -> Term.t -> Term.t
(** [term s j nonce = t_j(nonce)] for edge [s]. *)

val oracle : n:int -> Clutter.family -> Aset.t -> Loop.answer
(** The achievement oracle of the gadget for the given edges. Within one call,
    derivability results are cached per (sent messages, target). *)

type check = {
  trusts : int;  (** trusts compared: [2^n] *)
  agree : int;
      (** trusts on which both oracles give the same verdict and, on failure, the
          gadget's stopping set is an edge of [h] disjoint from the trust *)
  loop_w_equal : bool;  (** Algorithm 1 over the gadget returns [blocker h] *)
  loop_h_equal : bool;  (** ... and recovers [h] as its attacks *)
  gadget_distinct : int;  (** distinct oracle calls of that run *)
  time : float;  (** seconds for the whole check *)
}

val check : n:int -> Clutter.family -> check
(** Compare the gadget oracle with {!Synth.hypergraph_oracle} on all [2^n] trusts, then
    run {!Loop.weakest} over the gadget oracle. *)
