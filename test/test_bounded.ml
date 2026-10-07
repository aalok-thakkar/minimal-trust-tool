(* Tests of Bounded and Protocols: the paper's answers at pool size 1, replay
   consistency, monotonicity, and derivability against Dy. *)

open Trust
module P = Protocols

let passed = ref 0
let failed = ref 0

let check name cond =
  if cond then incr passed
  else (
    incr failed;
    Printf.printf "FAIL: %s\n%!" name)

let section name = Printf.printf "== %s\n%!" name
let set = Aset.of_list
let fam l = List.map set l
let feq = Clutter.equal_family
let pp_fam f = Format.asprintf "%a" Clutter.pp_family f

let loop ?(shrink = false) row mode =
  Loop.weakest ~shrink ~u:row.P.u (P.oracle row mode)

let subsets u =
  let atoms = Aset.elements u in
  List.init
    (1 lsl List.length atoms)
    (fun mask -> set (List.filteri (fun j _ -> mask land (1 lsl j) <> 0) atoms))

(* ---- derivability --------------------------------------------------------------- *)

let () =
  section "Bounded.derivable = Dy.derivable on random terms";
  let rng = Random.State.make [| 2026 |] in
  let names = [| "A"; "B"; "m"; "N"; "k"; "k2"; "pk_A"; "sk_A"; "pk_B"; "sk_B" |] in
  let rec gen d =
    if d = 0 || Random.State.int rng 3 = 0 then
      Term.name names.(Random.State.int rng (Array.length names))
    else
      let a = gen (d - 1) and b = gen (d - 1) in
      match Random.State.int rng 3 with
      | 0 -> Term.pair a b
      | 1 -> Term.enc a b
      | _ -> Term.sign a b
  in
  let fails = ref 0 in
  for _ = 1 to 3000 do
    let known = List.init (1 + Random.State.int rng 4) (fun _ -> gen 3) in
    let target = gen 3 in
    if Bounded.derivable known target <> Dy.derivable known target then begin
      incr fails;
      if !fails <= 3 then
        Printf.printf "  mismatch: known [%s] target %s\n"
          (String.concat "; " (List.map Term.to_string known))
          (Term.to_string target)
    end
  done;
  check "derivable agrees with Dy on 3000 random cases" (!fails = 0)

(* ---- the paper's answers ------------------------------------------------------------ *)

let () =
  section "analyser rows at pool size 1";
  let ska = "Non(sk_A)" and skb = "Non(sk_B)" and unq = "Unq(N)" in
  let w, h, st = loop P.signed_cr Bounded.Pruned in
  Printf.printf "  signed CR (pruned): W = %s, H = %s, %d calls\n" (pp_fam w) (pp_fam h)
    st.distinct;
  check "signed CR: W = {Non(sk_A), Unq(N)}" (feq w (fam [ [ ska; unq ] ]));
  check "signed CR: H = {Non(sk_A)}, {Unq(N)}" (feq h (fam [ [ ska ]; [ unq ] ]));
  check "signed CR: 3 distinct calls (pruned witnesses)" (st.distinct = 3);
  let w, _, st = loop P.signed_cr Bounded.As_found in
  check "signed CR as found: same W" (feq w (fam [ [ ska; unq ] ]));
  check "signed CR as found: 5 distinct calls" (st.distinct = 5);
  let m = P.signed_cr.model P.signed_cr.default_pool in
  (match (Bounded.search m ~u:P.signed_cr.u Bounded.As_found Aset.empty).outcome with
  | Bounded.Attack { stops; _ } ->
      check "Table 1: first witness as found has stops {Non(sk_A), Non(sk_B)}"
        (Aset.equal stops (set [ ska; skb ]))
  | Bounded.Achieves -> check "signed CR fails the empty trust" false);
  let w, h, st = loop P.two_key Bounded.Pruned in
  Printf.printf "  two-key (pruned): W = %s, H = %s, %d calls\n" (pp_fam w) (pp_fam h)
    st.distinct;
  check "two-key: antichain {Non(k1),Unq(N)}, {Non(k2),Unq(N)}"
    (feq w (fam [ [ "Non(k1)"; unq ]; [ "Non(k2)"; unq ] ]));
  check "two-key: H = {Unq(N)}, {Non(k1), Non(k2)}"
    (feq h (fam [ [ unq ]; [ "Non(k1)"; "Non(k2)" ] ]));
  check "two-key: 4 distinct calls" (st.distinct = 4);
  let w, h, st = loop P.nspk Bounded.As_found in
  check "NSPK: W = false" (w = []);
  check "NSPK: H = {{}}" (feq h [ Aset.empty ]);
  check "NSPK: 2 distinct calls (as found)" (st.distinct = 2);
  let w, _, st = loop P.nsl Bounded.As_found in
  check "NSL: W = {Non(sk_A)}" (feq w (fam [ [ ska ] ]));
  check "NSL: 2 distinct calls" (st.distinct = 2);
  let w, h, st = loop P.nspk_channels Bounded.Least in
  Printf.printf "  NSPK + channels: W = %s, H = %s, %d calls\n" (pp_fam w) (pp_fam h)
    st.distinct;
  check "NSPK + channels: W = {auth(A->B)}, {conf(B->A)}"
    (feq w (fam [ [ "auth(A->B)" ]; [ "conf(B->A)" ] ]));
  check "NSPK + channels: 3 distinct calls" (st.distinct = 3);
  let w, _, _ = loop P.nspk_channels_hijack Bounded.Least in
  check "NSPK + channels, hijack: W = {auth(A->B)}" (feq w (fam [ [ "auth(A->B)" ] ]));
  let w, _, _ = loop P.nsl_channels Bounded.Least in
  check "NSL + channels: W = {Non(sk_A)}, {auth(A->B)}, {conf(B->A)}"
    (feq w (fam [ [ ska ]; [ "auth(A->B)" ]; [ "conf(B->A)" ] ]))

(* ---- composition ----------------------------------------------------------------- *)

let () =
  section "composition";
  let ska = "Non(sk_A)" and skc = "Non(sk_C)" and unq = "Unq(N)" in
  let go v part goals = loop (P.composition v part goals) Bounded.Least in
  let join a b = Clutter.minimalize (List.concat_map (fun x -> List.map (Aset.union x) b) a) in
  let contains_member e f = List.exists (fun x -> Aset.subset x e) f in
  List.iter
    (fun v ->
      let w1, h1, _ = go v P.P1 P.Chi1 and w2, h2, _ = go v P.P2 P.Chi2 in
      check "P1 alone: {Non(sk_A), Unq(N)}" (feq w1 (fam [ [ ska; unq ] ]));
      check "P2 alone: {Non(sk_A)}" (feq w2 (fam [ [ ska ] ]));
      let wc, _, _ = go v P.Both P.Chi1_and_chi2 in
      let _, hc1, _ = go v P.Both P.Chi1 and _, hc2, _ = go v P.Both P.Chi2 in
      let cross1 = List.filter (fun e -> not (contains_member e h1)) hc1 in
      let cross2 = List.filter (fun e -> not (contains_member e h2)) hc2 in
      match v with
      | P.Tagged ->
          check "tagged: composition = join" (feq wc (join w1 w2));
          check "tagged: no cross-protocol stopping sets" (cross1 = [] && cross2 = [])
      | P.Untagged ->
          check "untagged: composition = false" (wc = []);
          check "untagged: cross-protocol {Non(sk_C)} on chi1" (feq cross1 (fam [ [ skc ] ]));
          check "untagged: cross-protocol {} on chi2" (feq cross2 [ Aset.empty ])
      | P.Separate_keys -> ())
    [ P.Tagged; P.Untagged ]

(* ---- replay, stops, monotonicity, brute force ------------------------------------- *)

let rows =
  [ P.signed_cr; P.two_key; P.signed_nonames; P.shared_nonames; P.nspk; P.nsl;
    P.nspk_channels; P.nsl_channels; P.nspk_channels_hijack;
    P.composition P.Untagged P.Both P.Chi1_and_chi2;
    P.composition P.Tagged P.Both P.Chi1_and_chi2 ]

let () =
  section "witness runs: replay, attack, stops by replay = tracked, single clause";
  List.iter
    (fun row ->
      let m = row.P.model row.P.default_pool in
      let u = row.P.u in
      List.iter
        (fun t ->
          List.iter
            (fun mode ->
              match (Bounded.search ~key_stops:row.P.key_stops m ~u mode t).outcome with
              | Bounded.Achieves -> ()
              | Bounded.Attack { run; stops } ->
                  let name = Printf.sprintf "%s %s" row.P.id (Aset.to_string t) in
                  check (name ^ ": witness replays") (Bounded.replays m t run);
                  check (name ^ ": witness is an attack") (Bounded.is_attack m t run);
                  check (name ^ ": stops disjoint from T") (Aset.disjoint stops t);
                  check (name ^ ": stops = replay") (Aset.equal stops (Bounded.stops m ~u t run));
                  check (name ^ ": clauses = [stops]")
                    (feq (Bounded.clauses m ~u t run) [ stops ]);
                  Aset.iter
                    (fun a ->
                      check (name ^ ": run fails under T + a for a in stops")
                        (not (Bounded.replays m (Aset.add a t) run)))
                    stops)
            [ Bounded.As_found; Bounded.Pruned; Bounded.Least ])
        (subsets u))
    rows;
  section "verdicts monotone, mode-independent; Loop = brute force in every mode";
  List.iter
    (fun row ->
      let ach mode =
        let o = P.oracle row mode in
        fun t -> o t = Loop.Achieves
      in
      let a = ach Bounded.As_found and b = ach Bounded.Pruned and c = ach Bounded.Least in
      let subs = subsets row.P.u in
      check (row.P.id ^ ": verdict independent of witness mode")
        (List.for_all (fun t -> a t = b t && b t = c t) subs);
      check (row.P.id ^ ": monotone")
        (List.for_all
           (fun t -> (not (a t)) || Aset.for_all (fun x -> a (Aset.add x t)) row.P.u)
           subs);
      let bf = Loop.brute_force ~u:row.P.u a in
      List.iter
        (fun mode ->
          List.iter
            (fun shrink ->
              let w, _, _ = loop ~shrink row mode in
              check (row.P.id ^ ": Loop = brute force") (feq w bf))
            [ false; true ])
        [ Bounded.As_found; Bounded.Pruned; Bounded.Least ])
    rows;
  section "reduction (block coalescing, symmetry): same verdicts and least stops";
  List.iter
    (fun row ->
      List.iter
        (fun pool ->
          let m = row.P.model pool in
          List.iter
            (fun t ->
              let full = Bounded.search m ~u:row.P.u Bounded.Least t in
              let red = Bounded.search ~reduce:true m ~u:row.P.u Bounded.Least t in
              let same =
                match (full.outcome, red.outcome) with
                | Bounded.Achieves, Bounded.Achieves -> true
                | Bounded.Attack a, Bounded.Attack b -> Aset.equal a.stops b.stops
                | _ -> false
              in
              check
                (Printf.sprintf "%s (%d inst., earlier %b) %s: reduced = full" row.P.id
                   pool.P.instances pool.P.earlier (Aset.to_string t))
                same)
            (subsets row.P.u))
        [ row.P.default_pool; { row.P.default_pool with P.earlier = not row.P.default_pool.earlier } ])
    rows;
  let m = P.nsl.model { P.instances = 2; earlier = false } in
  List.iter
    (fun t ->
      let a = Bounded.search m ~u:P.nsl.u Bounded.As_found t
      and b = Bounded.search ~reduce:true m ~u:P.nsl.u Bounded.As_found t in
      check ("NSL, 2 instances: reduced verdict = full " ^ Aset.to_string t)
        ((a.outcome = Bounded.Achieves) = (b.outcome = Bounded.Achieves));
      Printf.printf "  NSL 2 inst. %s: %d states full, %d reduced\n" (Aset.to_string t) a.states
        b.states)
    (* {Non(sk_A)} is left out: 14M states unreduced (about 3 minutes) *)
    (fam [ []; [ "Non(sk_B)" ]; [ "Non(sk_A)"; "Non(sk_B)" ] ]);
  section "pool parameter: instances 2 builds and agrees on NSPK = false";
  let w, _, _ =
    Loop.weakest ~u:P.nspk.u (P.oracle ~pool:{ P.instances = 2; earlier = true } P.nspk Bounded.As_found)
  in
  check "NSPK, 2 instances per role with an earlier session: false" (w = []);
  Printf.printf "bounded tests: %d passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
