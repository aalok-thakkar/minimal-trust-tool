(** The protocol rows of the bounded analyser (ports of [cr.py], [analyzer.py],
    [channels.py], [composition.py]), as {!Bounded} models.

    Every row is parameterised by a {!pool}: [instances] copies of each strand of the
    base pool (copy 1 is the base pool itself, with the Python names; copy [j >= 2]
    gets fresh nonces suffixed [.j] and is never a test strand), and whether an earlier
    completed honest session exists whose transcript the intruder holds. Instances and
    earlier session enlarge the variable pool by the new nonces. At [{instances = 1}]
    with the row's default [earlier], the model is the Python reference model. *)

type pool = { instances : int; earlier : bool }

type row = {
  id : string;
  title : string;
  u : Aset.t;  (** the generators *)
  situation : string;  (** the strand pool and what the situation fixes *)
  goal : string;
  default_pool : pool;
  model : pool -> Bounded.model;
  key_stops : bool;  (** visited key includes the broken atoms (as the Python engine) *)
  reference_mode : Bounded.mode;  (** the witness mode of the Python reference *)
  expected : Aset.t list option;  (** W(chi) stated in the paper, if any *)
}

val oracle :
  ?deadline:float ->
  ?reduce:bool ->
  ?key_stops:bool ->
  ?counter:Bounded.counter ->
  ?pool:pool ->
  row ->
  Bounded.mode ->
  Aset.t ->
  Loop.answer
(** [Bounded.oracle] on [row.model pool] (default [row.default_pool]) over [row.u];
    [key_stops] defaults to [row.key_stops]. *)

(** {2 Challenge-response (cr.py)}

    Strands (copy 1): 0 Chal(B,A) test [send N_t; recv resp(A,B,N_t)], 1 Prov(A,B),
    2 Prov(B,A), 3 Chal(A,B) on N_a, 4 Prov(A,I). Without Unq(N), and with an earlier
    session, the test nonce N_t is N (scenario ["N"], searched first) or the stale N_old
    (scenario ["N_old"]); Unq(N) removes the second scenario. Initial knowledge: names,
    public keys, sk_I, the earlier transcript [N_old, resp(A,B,N_old)], and every key of
    U not assumed. Goal (recent agreement): when the test strand completes, some
    Prov(A,B) strand sent resp(A,B,N_t) after the test strand sent N_t. *)

val signed_cr : row  (** resp(P,Q,n) = sig_{sk_P}(n,P,Q); U = sk_A, sk_B, N *)

val two_key : row  (** resp = {|{|n,P,Q|}_k1|}_k2; U = k1, k2, N *)

val signed_nonames : row  (** probe: sig_{sk_P}(n) *)

val shared_nonames : row  (** probe: {|n|}_{k_AB} *)

(** {2 Needham-Schroeder (analyzer.py, channels.py)}

    Strands (copy 1): 0 Init(A,B), 1 Init(A,I), 2 Resp(B,A) test; nonces Na_i, Nb_i by
    strand index. Messages travel on the channel from sender to intended receiver.
    Channel atoms exist for A->B and B->A only. The earlier session (off by default) is a
    completed Init(A,B)/Resp(B,A) run on Na_old, Nb_old whose three messages the intruder
    holds. Goal (non-injective agreement): when the test strand completes, some Init(A,B)
    strand has completed with the same (Na, Nb). *)

val nspk : row  (** U = sk_A, sk_B; as-found witnesses, as analyzer.py *)

val nsl : row
val nspk_channels : row  (** U = keys and auth/conf of A->B, B->A; least witnesses *)

val nsl_channels : row
val nspk_channels_hijack : row  (** with the Kamil-Lowe hijack transition *)

val nsl_channels_hijack : row

val nspk_keys_least : row
(** The NSPK keys-only row with least witnesses (channels.py's regression row). *)

val nsl_keys_least : row

val analyser_rows : row list
(** The five analyser rows of Table 2: signed CR, two-key, NSPK, NSPK with channels,
    NSL. *)

(** {2 Composition (composition.py)}

    P1: B_P1 [send N; recv sig(sk_A, <[cr,] N, A, B>)], A_P1 [recv n; send
    sig(sk_A, <[cr,] n, A, B>)]. P2: C_P2 [send sig(sk_C, <m_C, B>)], A_P2
    [recv sig(sk_C, <m, B>); send sig(k, <[att,] m, A, B>)], B_P2
    [recv sig(k, <[att,] M, A, B>)], with k = sk_A (shared) or sk_A2 (separate keys).
    U = {Non(sk_A), Non(sk_C), Unq(N)} (plus Non(sk_A2) for separate keys); Unq(N) keeps
    N out of the initial knowledge. Values {N, m_C, x}. chi1: when B_P1 completes, some
    A_P1 signed N after B_P1 sent it. chi2: when B_P2 accepts M, some A_P2 attested M.
    Least witnesses. *)

type variant = Tagged | Untagged | Separate_keys
type part = P1 | P2 | Both
type goals = Chi1 | Chi2 | Chi1_and_chi2

val composition : variant -> part -> goals -> row
val variant_name : variant -> string
