open Bounded

type pool = { instances : int; earlier : bool }

type row = {
  id : string;
  title : string;
  u : Aset.t;
  situation : string;
  goal : string;
  default_pool : pool;
  model : pool -> Bounded.model;
  key_stops : bool;
  reference_mode : Bounded.mode;
  expected : Aset.t list option;
}

let oracle ?deadline ?reduce ?key_stops ?counter ?pool row mode =
  let pool = Option.value pool ~default:row.default_pool in
  let key_stops = Option.value key_stops ~default:row.key_stops in
  Bounded.oracle ?deadline ~key_stops ?reduce ?counter (row.model pool) ~u:row.u mode

let n = Term.name
let pair = Term.pair
let set = Aset.of_list
let fam l = Some (List.map set l)
let non k = "Non(" ^ k ^ ")"
let sfx j s = if j = 1 then s else Printf.sprintf "%s.%d" s j
let send ?chan msg = { dir = Send; chan; msg }
let recv ?chan msg = { dir = Recv; chan; msg }
let tp a b = P (a, b)

(* strands of the copies, copy-major: copy 1 is the base pool *)
let copies k f = List.concat (List.init k (fun j -> f (j + 1)))

let indices_of strands label =
  Array.to_list strands
  |> List.mapi (fun i (s : strand) -> (i, s.label))
  |> List.filter_map (fun (i, l) -> if l = label then Some i else None)

(* ---- challenge-response -------------------------------------------------------- *)

let a_, b_, i_ = (n "A", n "B", n "I")
let unq = "Unq(N)"

type cr_proto = { keys : string list; resp : Term.t -> Term.t -> tmpl -> tmpl }

let cr_protos =
  [
    ( "signed",
      {
        keys = [ "sk_A"; "sk_B" ];
        resp =
          (fun p q m ->
            let s = match p with Term.Name x -> "sk_" ^ x | _ -> assert false in
            S (T (n s), tp m (T (pair p q))));
      } );
    ( "twokey",
      {
        keys = [ "k1"; "k2" ];
        resp = (fun p q m -> E (T (n "k2"), E (T (n "k1"), tp m (T (pair p q)))));
      } );
    ( "signed_nonames",
      {
        keys = [ "sk_A"; "sk_B" ];
        resp =
          (fun p _ m ->
            let s = match p with Term.Name x -> "sk_" ^ x | _ -> assert false in
            S (T (n s), m));
      } );
    ("shared_nonames", { keys = [ "k_AB" ]; resp = (fun _ _ m -> E (T (n "k_AB"), m)) });
  ]

let rec ground = function
  | T t -> t
  | V _ -> invalid_arg "ground"
  | P (a, b) -> Term.Pair (ground a, ground b)
  | E (a, b) -> Term.Enc (ground a, ground b)
  | S (a, b) -> Term.Sig (ground a, ground b)

let cr_model proto (pool : pool) =
  let pr = List.assoc proto cr_protos in
  let resp = pr.resp in
  let n_test = n "N" and n_old = n "N_old" in
  let strands =
    copies pool.instances (fun j ->
        let chal_nonce = if j = 1 then V "nt" else T (n (sfx j "N")) in
        let na = T (n (sfx j "N_a")) in
        [
          { label = (if j = 1 then "Chal(B,A)*" else sfx j "Chal(B,A)");
            steps = [ send chal_nonce; recv (resp a_ b_ chal_nonce) ] };
          { label = sfx j "Prov(A,B)"; steps = [ recv (V "n"); send (resp a_ b_ (V "n")) ] };
          { label = sfx j "Prov(B,A)"; steps = [ recv (V "n"); send (resp b_ a_ (V "n")) ] };
          { label = sfx j "Chal(A,B)"; steps = [ send na; recv (resp b_ a_ na) ] };
          { label = sfx j "Prov(A,I)"; steps = [ recv (V "n"); send (resp a_ i_ (V "n")) ] };
        ])
    |> Array.of_list
  in
  let values =
    [ a_; b_; i_; n_test ]
    @ (if pool.earlier then [ n_old ] else [])
    @ [ n "N_a" ]
    @ List.concat (List.init (pool.instances - 1) (fun j -> [ n (sfx (j + 2) "N"); n (sfx (j + 2) "N_a") ]))
  in
  let provs =
    List.filter_map
      (fun (i, (s : strand)) ->
        if String.length s.label >= 9 && String.sub s.label 0 9 = "Prov(A,B)" then Some i
        else None)
      (List.mapi (fun i s -> (i, s)) (Array.to_list strands))
  in
  let world t =
    let k0 =
      [ a_; b_; i_; n "pk_A"; n "pk_B"; n "pk_I"; n "sk_I" ]
      @ (if pool.earlier then [ n_old; ground (resp a_ b_ (T n_old)) ] else [])
      @ List.filter_map (fun k -> if Aset.mem (non k) t then None else Some (n k)) pr.keys
    in
    let sc v = { sname = (match v with Term.Name s -> s | _ -> "?"); fixed = [ (0, "nt", v) ] } in
    let scenarios =
      if Aset.mem unq t || not pool.earlier then [ sc n_test ] else [ sc n_test; sc n_old ]
    in
    { k0; auth = []; conf = []; scenarios }
  in
  let goal =
    {
      update =
        (fun v e ->
          if
            e.edir = Send && e.step = 1 && List.mem e.strand provs && v.pos.(0) >= 1
            && v.value e.strand "n" = v.value 0 "nt"
          then v.flags lor 1
          else v.flags);
      violated = (fun v -> v.pos.(0) = 2 && v.flags land 1 = 0);
    }
  in
  { strands; values; world; goal; test = [ 0 ]; hijack = false }

let cr_situation =
  "strands Chal(B,A)* (test), Prov(A,B), Prov(B,A), Chal(A,B), Prov(A,I); earlier completed \
   Prov(A,B) session on N_old in the intruder's knowledge; without Unq(N) the test nonce may be N_old"

let cr_row id proto title expected =
  let pr = List.assoc proto cr_protos in
  {
    id;
    title;
    u = set (List.map non pr.keys @ [ unq ]);
    situation = cr_situation;
    goal = "recent agreement of B with A";
    default_pool = { instances = 1; earlier = true };
    model = cr_model proto;
    key_stops = true;
    reference_mode = Pruned;
    expected;
  }

let signed_cr =
  cr_row "signed_cr" "signed" "signed CR" (fam [ [ non "sk_A"; unq ] ])

let two_key =
  cr_row "two_key" "twokey" "two-key variant"
    (fam [ [ non "k1"; unq ]; [ non "k2"; unq ] ])

let signed_nonames = cr_row "signed_nonames" "signed_nonames" "probe: signed, no names" None
let shared_nonames = cr_row "shared_nonames" "shared_nonames" "probe: shared key, no names" None

(* ---- Needham-Schroeder ------------------------------------------------------------ *)

let pk x = n ("pk_" ^ x)
let honest_channels = [ ("A", "B"); ("B", "A") ]
let chan_atom lvl (x, y) = Printf.sprintf "%s(%s->%s)" lvl x y

let chan_atoms =
  List.concat_map (fun c -> [ chan_atom "auth" c; chan_atom "conf" c ]) honest_channels

let ns_model ~nsl ~hijack (pool : pool) =
  let body2 na nb b = if nsl then tp na (tp nb (T (n b))) else tp na nb in
  let init sid a b =
    let na = T (n (Printf.sprintf "Na_%d" sid)) in
    {
      label = Printf.sprintf "Init(%s,%s)" a b ^ if sid >= 3 then Printf.sprintf ".%d" sid else "";
      steps =
        [
          send ~chan:(a, b) (E (T (pk b), tp na (T (n a))));
          recv ~chan:(b, a) (E (T (pk a), body2 na (V "Nb") b));
          send ~chan:(a, b) (E (T (pk b), V "Nb"));
        ];
    }
  in
  let resp sid b a =
    let nb = T (n (Printf.sprintf "Nb_%d" sid)) in
    {
      label = (Printf.sprintf "Resp(%s,%s)" b a ^ if sid = 2 then "*" else Printf.sprintf ".%d" sid);
      steps =
        [
          recv ~chan:(a, b) (E (T (pk b), tp (V "Na") (T (n a))));
          send ~chan:(b, a) (E (T (pk a), body2 (V "Na") nb b));
          recv ~chan:(a, b) (E (T (pk b), nb));
        ];
    }
  in
  let strands =
    copies pool.instances (fun j ->
        let base = 3 * (j - 1) in
        [ init base "A" "B"; init (base + 1) "A" "I"; resp (base + 2) "B" "A" ])
    |> Array.of_list
  in
  let own =
    List.concat
      (List.init pool.instances (fun j ->
           let base = 3 * j in
           [
             Printf.sprintf "Na_%d" base;
             Printf.sprintf "Na_%d" (base + 1);
             Printf.sprintf "Nb_%d" (base + 2);
           ]))
  in
  let earlier_nonces = if pool.earlier then [ "Na_old"; "Nb_old" ] else [] in
  let values = List.map n (List.sort compare ([ "A"; "B"; "I" ] @ own @ earlier_nonces)) in
  let inits = List.init pool.instances (fun j -> 3 * j) in
  let transcript =
    if not pool.earlier then []
    else
      let na = T (n "Na_old") and nb = T (n "Nb_old") in
      List.map ground
        [
          E (T (pk "B"), tp na (T a_));
          E (T (pk "A"), body2 na nb "B");
          E (T (pk "B"), nb);
        ]
  in
  let world t =
    let k0 =
      [ a_; b_; i_; pk "A"; pk "B"; pk "I"; n "sk_I" ]
      @ List.filter_map
          (fun x -> if Aset.mem (non ("sk_" ^ x)) t then None else Some (n ("sk_" ^ x)))
          [ "A"; "B" ]
      @ transcript
    in
    let chans lvl = List.filter (fun c -> Aset.mem (chan_atom lvl c) t) honest_channels in
    {
      k0;
      auth = chans "auth";
      conf = chans "conf";
      scenarios = [ { sname = "main"; fixed = [] } ];
    }
  in
  let nb2 = n "Nb_2" in
  let goal =
    {
      update = (fun v _ -> v.flags);
      violated =
        (fun v ->
          v.pos.(2) = 3
          && not
               (List.exists
                  (fun i ->
                    v.pos.(i) = 3
                    && v.value 2 "Na" = Some (n (Printf.sprintf "Na_%d" i))
                    && v.value i "Nb" = Some nb2)
                  inits));
    }
  in
  { strands; values; world; goal; test = [ 2 ]; hijack }

let ns_situation =
  "strands Init(A,B), Init(A,I), Resp(B,A)* (test); every nonce a distinct fresh atom"

let ns_row ~id ~title ~nsl ~channels ~hijack ~mode ~key_stops expected =
  let keys = [ non "sk_A"; non "sk_B" ] in
  {
    id;
    title;
    u = set (keys @ if channels then chan_atoms else []);
    situation = ns_situation;
    goal = "responder's non-injective agreement with the initiator on (Na, Nb)";
    default_pool = { instances = 1; earlier = false };
    model = ns_model ~nsl ~hijack;
    key_stops;
    reference_mode = mode;
    expected;
  }

let nspk =
  ns_row ~id:"nspk" ~title:"Needham-Schroeder" ~nsl:false ~channels:false ~hijack:false
    ~mode:As_found ~key_stops:false (Some [])

let nsl =
  ns_row ~id:"nsl" ~title:"Lowe's fix (NSL)" ~nsl:true ~channels:false ~hijack:false
    ~mode:As_found ~key_stops:false
    (fam [ [ non "sk_A" ] ])

let nspk_keys_least =
  ns_row ~id:"nspk_keys_least" ~title:"NSPK, keys (least witnesses)" ~nsl:false
    ~channels:false ~hijack:false ~mode:Least ~key_stops:true (Some [])

let nsl_keys_least =
  ns_row ~id:"nsl_keys_least" ~title:"NSL, keys (least witnesses)" ~nsl:true
    ~channels:false ~hijack:false ~mode:Least ~key_stops:true
    (fam [ [ non "sk_A" ] ])

let nspk_channels =
  ns_row ~id:"nspk_channels" ~title:"NSPK with channels" ~nsl:false ~channels:true
    ~hijack:false ~mode:Least ~key_stops:true
    (fam [ [ "auth(A->B)" ]; [ "conf(B->A)" ] ])

let nsl_channels =
  ns_row ~id:"nsl_channels" ~title:"NSL with channels" ~nsl:true ~channels:true
    ~hijack:false ~mode:Least ~key_stops:true
    (fam [ [ non "sk_A" ]; [ "auth(A->B)" ]; [ "conf(B->A)" ] ])

let nspk_channels_hijack =
  ns_row ~id:"nspk_channels_hijack" ~title:"NSPK with channels, hijack" ~nsl:false
    ~channels:true ~hijack:true ~mode:Least ~key_stops:true
    (fam [ [ "auth(A->B)" ] ])

let nsl_channels_hijack =
  ns_row ~id:"nsl_channels_hijack" ~title:"NSL with channels, hijack" ~nsl:true
    ~channels:true ~hijack:true ~mode:Least ~key_stops:true None

let analyser_rows = [ signed_cr; two_key; nspk; nspk_channels; nsl ]

(* ---- composition ------------------------------------------------------------------ *)

type variant = Tagged | Untagged | Separate_keys
type part = P1 | P2 | Both
type goals = Chi1 | Chi2 | Chi1_and_chi2

let variant_name = function
  | Tagged -> "tagged"
  | Untagged -> "untagged"
  | Separate_keys -> "separate_keys"

let composition variant part goals =
  let tagged = variant = Tagged in
  let att_key = if variant = Separate_keys then "sk_A2" else "sk_A" in
  let c_ = n "C" and n_ = n "N" and mc = n "m_C" and x = n "x" in
  let cr_tag = n "cr" and att_tag = n "att" in
  let body tag v = if tagged then tp (T tag) (tp v (T (pair a_ b_))) else tp v (T (pair a_ b_)) in
  let sk s = T (n s) in
  let p1 j =
    let nn = if j = 1 then T n_ else T (n (sfx j "N")) in
    [
      { label = sfx j "B_P1"; steps = [ send nn; recv (S (sk "sk_A", body cr_tag nn)) ] };
      { label = sfx j "A_P1"; steps = [ recv (V "n"); send (S (sk "sk_A", body cr_tag (V "n"))) ] };
    ]
  in
  let p2 j =
    let m = if j = 1 then T mc else T (n (sfx j "m_C")) in
    [
      { label = sfx j "C_P2"; steps = [ send (S (sk "sk_C", tp m (T b_))) ] };
      {
        label = sfx j "A_P2";
        steps =
          [ recv (S (sk "sk_C", tp (V "m") (T b_))); send (S (sk att_key, body att_tag (V "m"))) ];
      };
      { label = sfx j "B_P2"; steps = [ recv (S (sk att_key, body att_tag (V "M"))) ] };
    ]
  in
  let atoms_terms =
    [ (non "sk_A", n "sk_A"); (non "sk_C", n "sk_C"); (unq, n_) ]
    @ if variant = Separate_keys then [ (non "sk_A2", n "sk_A2") ] else []
  in
  let u = set (List.map fst atoms_terms) in
  let model (pool : pool) =
    let strands =
      copies pool.instances (fun j ->
          match part with P1 -> p1 j | P2 -> p2 j | Both -> p1 j @ p2 j)
      |> Array.of_list
    in
    let idx l = indices_of strands l in
    let b1 = List.nth_opt (idx "B_P1") 0 and b2 = List.nth_opt (idx "B_P2") 0 in
    let a1s =
      List.concat (List.init pool.instances (fun j -> idx (sfx (j + 1) "A_P1")))
    and a2s = List.concat (List.init pool.instances (fun j -> idx (sfx (j + 1) "A_P2"))) in
    let values =
      [ n_; mc; x ]
      @ List.concat
          (List.init (pool.instances - 1) (fun j -> [ n (sfx (j + 2) "N"); n (sfx (j + 2) "m_C") ]))
    in
    let world t =
      let k0 =
        [ a_; b_; c_; i_; x; cr_tag; att_tag ]
        @ List.filter_map (fun (a, k) -> if Aset.mem a t then None else Some k) atoms_terms
      in
      { k0; auth = []; conf = []; scenarios = [ { sname = "main"; fixed = [] } ] }
    in
    let chi1 v =
      match b1 with
      | Some b -> v.pos.(b) >= 2 && v.flags land 1 = 0
      | None -> false
    in
    let chi2 v =
      match b2 with
      | Some b ->
          v.pos.(b) >= 1
          && not (List.exists (fun a -> v.pos.(a) >= 2 && v.value a "m" = v.value b "M") a2s)
      | None -> false
    in
    let goal =
      {
        update =
          (fun v e ->
            match b1 with
            | Some b
              when e.edir = Send && e.step = 1 && List.mem e.strand a1s && v.pos.(b) >= 1
                   && v.value e.strand "n" = Some n_ ->
                v.flags lor 1
            | _ -> v.flags);
        violated =
          (fun v ->
            match goals with
            | Chi1 -> chi1 v
            | Chi2 -> chi2 v
            | Chi1_and_chi2 -> chi1 v || chi2 v);
      }
    in
    let test = List.filter_map Fun.id [ b1; b2 ] in
    { strands; values; world; goal; test; hijack = false }
  in
  let pname = match part with P1 -> "P1" | P2 -> "P2" | Both -> "P1||P2" in
  let gname = match goals with Chi1 -> "chi1" | Chi2 -> "chi2" | Chi1_and_chi2 -> "chi1&chi2" in
  {
    id = Printf.sprintf "compose_%s_%s_%s" (variant_name variant) pname gname;
    title = Printf.sprintf "%s, %s, %s" (variant_name variant) pname gname;
    u;
    situation =
      "one strand per role: B_P1, A_P1 (P1); C_P2, A_P2, B_P2 (P2); values N, m_C, x";
    goal =
      (match goals with
      | Chi1 -> "chi1: recent agreement of B_P1 with A on N"
      | Chi2 -> "chi2: agreement of B_P2 with A on M"
      | Chi1_and_chi2 -> "chi1 and chi2");
    default_pool = { instances = 1; earlier = false };
    model;
    key_stops = true;
    reference_mode = Least;
    expected = None;
  }
