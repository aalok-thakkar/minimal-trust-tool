(* Unit and property tests. Own harness; every random test uses an explicit
   Random.State with a fixed seed, so runs are reproducible. *)

open Trust

let passed = ref 0
let failed = ref 0

let check name cond =
  if cond then incr passed
  else (
    incr failed;
    Printf.printf "FAIL: %s\n%!" name)

let section name = Printf.printf "== %s\n%!" name
let set l = Aset.of_list l
let fam l = List.map set l
let feq = Clutter.equal_family

(* Property harness: [count] cases drawn from [gen rng]; prints at most 5
   counterexamples. *)
let forall ~name ~seed ~count gen prop show =
  let rng = Random.State.make [| seed |] in
  let fails = ref 0 in
  for i = 1 to count do
    let x = gen rng in
    let ok =
      try prop rng x
      with e ->
        Printf.printf "  exception %s\n" (Printexc.to_string e);
        false
    in
    if ok then incr passed
    else (
      incr failed;
      incr fails;
      if !fails <= 5 then
        Printf.printf "FAIL: %s (seed %d, case %d): %s\n%!" name seed i (show x))
  done;
  Printf.printf "  %s: %d cases, %d failures\n%!" name count !fails

(* ---- generators ------------------------------------------------------------ *)

let atoms n = List.init n (fun i -> Printf.sprintf "x%d" i)

(* k distinct atoms of u, uniformly (Fisher-Yates prefix) *)
let random_k_subset rng k u =
  let arr = Array.of_list u in
  for i = Array.length arr - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let t = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- t
  done;
  Aset.of_list (Array.to_list (Array.sub arr 0 k))

(* Random family over n <= 10 atoms: m in 0..2n edges, edge sizes 1..min(n,4),
   and an empty edge with probability 1/40. *)
let gen_family rng =
  let n = 1 + Random.State.int rng 10 in
  let u = atoms n in
  let m = Random.State.int rng ((2 * n) + 1) in
  let edge () =
    if Random.State.int rng 40 = 0 then Aset.empty
    else
      let k = 1 + Random.State.int rng (min n 4) in
      random_k_subset rng k u
  in
  (set u, List.init m (fun _ -> edge ()))

let show_family (u, h) = Format.asprintf "U=%a H=%a" Aset.pp u Clutter.pp_family h

(* ---- hitting.py _test ------------------------------------------------------ *)

let test_clutter () =
  section "Clutter (hitting.py _test)";
  let a = "a" and b = "b" and c = "c" in
  check "blocker {a}" (feq (Clutter.blocker (fam [ [ a ] ])) (fam [ [ a ] ]));
  check "blocker {a,b}" (feq (Clutter.blocker (fam [ [ a; b ] ])) (fam [ [ a ]; [ b ] ]));
  check "minimalize subsumption"
    (feq (Clutter.minimalize (fam [ [ a ]; [ a; b ] ])) (fam [ [ a ] ]));
  check "blocker subsumption"
    (feq (Clutter.blocker (fam [ [ a ]; [ a; b ] ])) (fam [ [ a ] ]));
  check "crossing"
    (feq (Clutter.blocker (fam [ [ a; b ]; [ b; c ] ])) (fam [ [ b ]; [ a; c ] ]));
  check "blocker [] = [{}]" (feq (Clutter.blocker []) [ Aset.empty ]);
  check "blocker [{}] = []" (Clutter.blocker [ Aset.empty ] = []);
  List.iter
    (fun h ->
      check "involution" (feq (Clutter.blocker (Clutter.blocker h)) (Clutter.minimalize h)))
    [
      fam [ [ a; b ] ];
      fam [ [ a; b ]; [ b; c ] ];
      fam [ [ a ]; [ b; c ] ];
      fam [ [ a; b ]; [ a; c ]; [ b; c ] ];
    ];
  check "minimalize order"
    (List.equal Aset.equal
       (Clutter.minimalize (fam [ [ c ]; [ a; b ]; [ b ]; [ a; c ]; [ c ] ]))
       (fam [ [ b ]; [ c ] ]));
  check "sort order"
    (List.equal Aset.equal
       (Clutter.sort (fam [ [ b; c ]; [ a ]; [ a; c ]; [ a; b ]; [ a ] ]))
       (fam [ [ a ]; [ a; b ]; [ a; c ]; [ b; c ] ]));
  check "is_transversal" (Clutter.is_transversal (set [ b ]) (fam [ [ a; b ]; [ b; c ] ]));
  check "not is_transversal"
    (not (Clutter.is_transversal (set [ a ]) (fam [ [ a; b ]; [ b; c ] ])));
  check "hits" (Clutter.hits (set [ a; b ]) (set [ b; c ]))

(* ---- cegis.py _test, plus Section 2 answers ------------------------------- *)

let fails ?(descr = "") l = Loop.Fails { Loop.stops = set l; descr }

let test_loop_units () =
  section "Loop (cegis.py _test; Section 2 answers via mock oracles)";
  let skA = "skA" and skB = "skB" in
  let u2 = set [ skA; skB ] in
  (* Case 1: forgery stopped only by skA *)
  let w, _, _ =
    Loop.weakest ~u:u2 (fun t ->
        if not (Aset.mem skA t) then fails ~descr:"forgery" [ skA ] else Loop.Achieves)
  in
  check "names: W = {{skA}}" (feq w (fam [ [ skA ] ]));
  (* Case 2: either key stops the impersonation *)
  let w, _, _ =
    Loop.weakest ~u:u2 (fun t ->
        if (not (Aset.mem skA t)) && not (Aset.mem skB t) then fails [ skA; skB ]
        else Loop.Achieves)
  in
  check "either: W = {{skA},{skB}}" (feq w (fam [ [ skA ]; [ skB ] ]));
  (* Three-conflict case *)
  let conf = fam [ [ "a" ]; [ "b"; "c" ] ] in
  let oracle3 t =
    match List.find_opt (fun e -> not (Clutter.hits t e)) conf with
    | Some e -> Loop.Fails { stops = e; descr = "" }
    | None -> Loop.Achieves
  in
  let u3 = set [ "a"; "b"; "c" ] in
  let w, h, st = Loop.weakest ~u:u3 oracle3 in
  check "oracle3 W" (feq w (fam [ [ "a"; "b" ]; [ "a"; "c" ] ]));
  check "oracle3 H" (feq h conf);
  check "memo: distinct <= queries" (st.distinct <= st.queries);
  (* Padded witnesses *)
  let u = set [ "a"; "b"; "c"; "d" ] in
  let padded t =
    match List.find_opt (fun e -> not (Clutter.hits t e)) conf with
    | Some e -> Loop.Fails { stops = Aset.diff (Aset.add "d" e) t; descr = "padded" }
    | None -> Loop.Achieves
  in
  let w0, h0, st0 = Loop.weakest ~u padded in
  let w1, h1, st1 = Loop.weakest ~shrink:true ~u padded in
  let want = fam [ [ "a"; "b" ]; [ "a"; "c" ] ] in
  check "padded plain W" (feq w0 want);
  check "padded shrink W" (feq w1 want);
  check "padded shrink H" (feq h1 conf);
  check "padded plain H = attacks (involution)" (feq h0 conf);
  Format.printf "  padded: plain %a; shrink %a@." Loop.pp_stats st0 Loop.pp_stats st1;
  (* Section 2 running example over U = {Non(sk_A), Unq(N)}: forgery stopped by
     Non(sk_A), replay by Unq(N) (and by nothing else). W = {{Non(sk_A), Unq(N)}}. *)
  let ska = "Non(sk_A)" and unq = "Unq(N)" in
  let u = set [ ska; unq ] in
  let signed t =
    if not (Aset.mem ska t) then fails ~descr:"forgery" [ ska ]
    else if not (Aset.mem unq t) then fails ~descr:"replay" [ unq ]
    else Loop.Achieves
  in
  let w, h, st = Loop.weakest ~u signed in
  check "signed CR W" (feq w (fam [ [ ska; unq ] ]));
  check "signed CR H" (feq h (fam [ [ ska ]; [ unq ] ]));
  check "signed CR distinct = 3" (st.distinct = 3);
  (* two-key variant: forgery stopped by either key, replay by Unq(N) *)
  let k1 = "Non(k1)" and k2 = "Non(k2)" in
  let u = set [ k1; k2; unq ] in
  let twokey t =
    if (not (Aset.mem k1 t)) && not (Aset.mem k2 t) then fails ~descr:"forgery" [ k1; k2 ]
    else if not (Aset.mem unq t) then fails ~descr:"replay" [ unq ]
    else Loop.Achieves
  in
  let w, h, st = Loop.weakest ~u twokey in
  check "two-key W" (feq w (fam [ [ k1; unq ]; [ k2; unq ] ]));
  check "two-key H" (feq h (fam [ [ k1; k2 ]; [ unq ] ]));
  check "two-key distinct = 4" (st.distinct = 4);
  (* unrealisable: empty stopping set *)
  let w, h, st = Loop.weakest ~u (fun _ -> fails ~descr:"NSPK" []) in
  check "false: W = []" (w = []);
  check "false: H = [{}]" (feq h [ Aset.empty ]);
  check "false: distinct = 1" (st.distinct = 1);
  (* soundness checks raise *)
  let raises f = try ignore (f ()); false with Loop.Unsound_witness _ -> true in
  check "unsound: stops meets trust"
    (raises (fun () -> Loop.weakest ~u (fun _ -> fails [ ska ])));
  check "unsound: stops outside U"
    (raises (fun () -> Loop.weakest ~u (fun _ -> fails [ "zzz" ])));
  (* baselines on the two-key oracle *)
  let pred t = twokey t = Loop.Achieves in
  check "brute_force two-key" (feq (Loop.brute_force ~u pred) (fam [ [ k1; unq ]; [ k2; unq ] ]));
  let lw = Loop.levelwise ~u pred in
  check "levelwise two-key" (lw.complete && feq lw.found (fam [ [ k1; unq ]; [ k2; unq ] ]));
  let lw2 = Loop.levelwise ~budget:2 ~u pred in
  check "levelwise budget" ((not lw2.complete) && lw2.calls = 2);
  (match Loop.greedy_rgl ~u pred with
  | Some t, calls -> check "greedy two-key" (Aset.equal t (set [ k2; unq ]) && calls = 4)
  | None, _ -> check "greedy two-key" false);
  check "greedy none" (Loop.greedy_rgl ~u (fun _ -> false) = (None, 1))

(* ---- property tests ---------------------------------------------------------- *)

let test_blocker_props () =
  section "Clutter properties";
  forall ~name:"blocker(blocker(H)) = minimalize(H)" ~seed:1 ~count:2000 gen_family
    (fun _ (_, h) -> feq (Clutter.blocker (Clutter.blocker h)) (Clutter.minimalize h))
    show_family;
  forall ~name:"blocker(H) = brute-force minimal transversals" ~seed:2 ~count:1000
    gen_family
    (fun _ (u, h) ->
      List.equal Aset.equal (Clutter.blocker h)
        (Loop.brute_force ~u (fun t -> Clutter.is_transversal t h)))
    show_family;
  forall ~name:"minimalize is a clutter, keeps a subset of every member" ~seed:3
    ~count:2000 gen_family
    (fun _ (_, h) ->
      let m = Clutter.minimalize h in
      List.for_all (fun s -> List.exists (fun t -> Aset.subset t s) m) h
      && List.for_all
           (fun s -> List.for_all (fun t -> Aset.equal s t || not (Aset.subset t s)) m)
           m
      && List.equal Aset.equal m (Clutter.sort m))
    show_family;
  forall ~name:"minimalize = naive definition" ~seed:4 ~count:2000 gen_family
    (fun _ (_, h) ->
      let naive =
        List.filter
          (fun s -> not (List.exists (fun t -> Aset.subset t s && not (Aset.equal t s)) h))
          h
      in
      List.equal Aset.equal (Clutter.minimalize h) (Clutter.sort naive))
    show_family;
  forall ~name:"involution, n <= 16, up to 48 edges of size <= 6" ~seed:5 ~count:200
    (fun rng ->
      let n = 1 + Random.State.int rng 16 in
      let u = atoms n in
      let m = Random.State.int rng 49 in
      ( set u,
        List.init m (fun _ ->
            random_k_subset rng (1 + Random.State.int rng (min n 6)) u) ))
    (fun _ (_, h) -> feq (Clutter.blocker (Clutter.blocker h)) (Clutter.minimalize h))
    show_family

type mode = Minimal | Padded | Padded_shrink

let mode_name = function
  | Minimal -> "minimal"
  | Padded -> "padded"
  | Padded_shrink -> "padded+shrink"

(* oracle for the monotone property "t meets every member of a": the witness is the
   first unhit member of a (canonical order), padded in the padded modes with random
   atoms of U \ t *)
let make_oracle mode rng u a t =
  match List.find_opt (fun e -> not (Clutter.hits t e)) a with
  | None -> Loop.Achieves
  | Some e ->
      let stops =
        match mode with
        | Minimal -> e
        | Padded | Padded_shrink ->
            Aset.union e
              (Aset.filter (fun _ -> Random.State.bool rng) (Aset.diff u t))
      in
      Loop.Fails { stops; descr = "edge " ^ Aset.to_string e }

let test_loop_props () =
  section "Loop properties (random monotone oracles, n <= 10)";
  List.iteri
    (fun i mode ->
      forall
        ~name:("weakest = brute force, H = attacks, call bound: " ^ mode_name mode)
        ~seed:(10 + i) ~count:1000 gen_family
        (fun rng (u, h) ->
          let a = Clutter.minimalize h in
          let w, h', st =
            Loop.weakest ~shrink:(mode = Padded_shrink) ~u (make_oracle mode rng u a)
          in
          let bf = Loop.brute_force ~u (fun t -> Clutter.is_transversal t a) in
          let nw = List.length w and nh = List.length h' and nu = Aset.cardinal u in
          let bound =
            match mode with
            | Minimal -> st.distinct <= nh + nw
            | Padded -> true
            | Padded_shrink -> st.distinct <= nw + (nh * (1 + nu))
          in
          List.equal Aset.equal w bf && List.equal Aset.equal h' a && bound
          && st.distinct <= st.queries + st.shrink_calls
          && (mode = Padded_shrink || st.iterations = st.distinct - nw + 1))
        show_family)
    [ Minimal; Padded; Padded_shrink ];
  forall ~name:"levelwise = brute force; greedy in W" ~seed:20 ~count:500 gen_family
    (fun _ (u, h) ->
      let a = Clutter.minimalize h in
      let pred t = Clutter.is_transversal t a in
      let bf = Loop.brute_force ~u pred in
      let lw = Loop.levelwise ~u pred in
      let g, calls = Loop.greedy_rgl ~u pred in
      lw.complete
      && List.equal Aset.equal lw.found bf
      && (match g with
         | None -> bf = [] && calls = 1
         | Some t -> List.exists (Aset.equal t) bf && calls = 1 + Aset.cardinal u))
    show_family

(* ---- Dy ---------------------------------------------------------------------- *)

let test_dy () =
  section "Dy (dy.py _test and further cases)";
  let open Term in
  let a = name "A" and b = name "B" in
  let kab = name "k_AB" and ska = name "sk_A" and pka = name "pk_A" in
  let m = name "m" and n = name "N" in
  let d = Dy.derivable in
  check "sym dec" (d [ kab; enc kab m ] m);
  check "sym dec needs key" (not (d [ enc kab m ] m));
  check "sym enc" (d [ kab; m ] (enc kab m));
  check "sym enc needs key" (not (d [ m ] (enc kab m)));
  check "pk dec with sk" (d [ ska; enc pka m ] m);
  check "pk dec needs sk" (not (d [ pka; enc pka m ] m));
  check "sig exposes" (d [ sign ska m ] m);
  check "sign with key" (d [ ska; m ] (sign ska m));
  check "no forgery" (not (d [ m; pka ] (sign ska m)));
  check "projection" (d [ pair a b ] a && d [ pair a b ] b);
  check "pairing" (d [ a; b ] (pair a b));
  check "nested N" (d [ kab; enc kab (pair n m) ] n);
  check "nested m" (d [ kab; enc kab (pair n m) ] m);
  (* further cases *)
  check "inverse pk/sk" (inverse pka = ska && inverse ska = pka && inverse kab = kab);
  check "key inside another ciphertext" (d [ enc kab (pair kab m) ] m = false);
  check "key delivered in a pair" (d [ pair kab (enc kab m) ] m);
  check "chain of keys" (d [ name "k1"; enc (name "k1") (name "k2"); enc (name "k2") m ] m);
  check "compound symmetric key" (d [ a; b; enc (pair a b) m ] m);
  check "compose under learnt key"
    (d [ enc kab n; kab; m ] (enc kab (pair n m)));
  check "cannot open pk ciphertext with pk" (not (d [ pka; enc pka (pair n m) ] n));
  check "target not in knowledge, atom" (not (d [ a; b ] m));
  check "sign of composed message" (d [ ska; a; n ] (sign ska (pair a n)));
  check "enc under sig-exposed key" (d [ sign ska kab; enc kab m ] m)

let () =
  test_clutter ();
  test_loop_units ();
  test_blocker_props ();
  test_loop_props ();
  test_dy ();
  Printf.printf "\n%d passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
