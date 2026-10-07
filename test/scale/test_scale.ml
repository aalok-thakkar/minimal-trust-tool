(* Tests for Synth and Gadget (experiment E3). Every random case uses an explicit,
   seeded Random.State. *)

open Trust

let passed = ref 0
let failed = ref 0

let check name cond =
  if cond then incr passed
  else (
    incr failed;
    Printf.printf "FAIL: %s\n%!" name)

let feq = Clutter.equal_family

(* Synth: atoms, fixed families and their blockers. *)
let test_synth () =
  check "atom/index" (List.for_all (fun i -> Synth.index (Synth.atom i) = i) (List.init 100 Fun.id));
  check "atom order = numeric order"
    (List.map Synth.index (Aset.elements (Synth.universe 30)) = List.init 30 Fun.id);
  for n = 2 to 12 do
    if n mod 2 = 0 then begin
      check (Printf.sprintf "blocker pairs %d = dual" n)
        (feq (Clutter.blocker (Synth.disjoint_pairs n)) (Synth.dual_pairs n));
      check (Printf.sprintf "|dual %d| = 2^(n/2)" n)
        (List.length (Synth.dual_pairs n) = 1 lsl (n / 2))
    end
  done;
  for s = 1 to 8 do
    for k = 1 to s do
      check (Printf.sprintf "threshold blocker s=%d k=%d" s k)
        (feq (Clutter.blocker (Synth.threshold ~s ~k)) (Synth.threshold ~s ~k:(s - k + 1)))
    done
  done;
  let rng = Synth.random_state ~family:"x" ~n:10 ~m:20 ~seed:3 in
  let h = Synth.random rng ~n:10 ~m:20 in
  let h' = Synth.random (Synth.random_state ~family:"x" ~n:10 ~m:20 ~seed:3) ~n:10 ~m:20 in
  check "random is a function of the state" (List.equal Aset.equal h h');
  check "random is a clutter" (List.equal Aset.equal (Clutter.minimalize h) h);
  check "random edge sizes 1-3"
    (List.for_all (fun e -> let k = Aset.cardinal e in k >= 1 && k <= 3) h)

(* Loop on 200 random instances, n <= 12: W = brute force, distinct = |H| + |W|, every
   witness minimal (H recovered exactly); padded witnesses with shrinking within the
   Theorem thm:cost bound. *)
let test_loop () =
  let bad = ref 0 in
  for case = 0 to 199 do
    let rng = Random.State.make [| 4242; case |] in
    let n = 1 + Random.State.int rng 12 in
    let m = 1 + Random.State.int rng (4 * n) in
    let h = Synth.random rng ~n ~m in
    let u = Synth.universe n in
    let witnesses = ref [] in
    let oracle t =
      let r = Synth.hypergraph_oracle h t in
      (match r with Loop.Fails w -> witnesses := w.stops :: !witnesses | _ -> ());
      r
    in
    let w, h', st = Loop.weakest ~u oracle in
    let bf = Loop.brute_force ~u (Synth.achieves h) in
    let minimal_witnesses = List.for_all (fun s -> List.exists (Aset.equal s) h) !witnesses in
    let ok_min =
      List.equal Aset.equal w bf && feq h' h
      && st.distinct = List.length h + List.length w
      && minimal_witnesses
    in
    let pw, ph, pst =
      Loop.weakest ~shrink:true ~u (Synth.padded_oracle (Random.State.make [| case |]) ~u h)
    in
    let ok_pad =
      List.equal Aset.equal pw bf && feq ph h
      && pst.distinct <= List.length pw + (List.length h * (1 + n))
    in
    if not (ok_min && ok_pad) then (
      incr bad;
      if !bad <= 5 then
        Format.printf "  case %d: n=%d H=%a min=%b pad=%b@." case n Clutter.pp_family h ok_min
          ok_pad)
  done;
  check "loop vs brute force on 200 random instances (n <= 12)" (!bad = 0);
  Printf.printf "  loop vs brute force: 200 cases, %d failures\n%!" !bad

(* Gadget: exhaustive agreement with the hypergraph oracle on a few n <= 5 instances. *)
let test_gadget () =
  let cases =
    [
      (4, [ [ 0; 1 ]; [ 1; 2 ]; [ 3 ] ]);
      (4, [ [ 0 ]; [ 1; 2; 3 ] ]);
      (4, [ [ 0; 1 ]; [ 2; 3 ] ]);
      (5, [ [ 0; 1; 2 ]; [ 2; 3 ]; [ 4; 0 ] ]);
    ]
    |> List.map (fun (n, e) -> (n, Synth.of_indices e))
  in
  let rand =
    List.init 3 (fun seed ->
        (5, Synth.random (Synth.random_state ~family:"test-gadget" ~n:5 ~m:3 ~seed) ~n:5 ~m:3))
  in
  List.iter
    (fun (n, h) ->
      let c = Gadget.check ~n h in
      check
        (Format.asprintf "gadget agrees on n=%d H=%a" n Clutter.pp_family h)
        (c.agree = c.trusts && c.trusts = 1 lsl n && c.loop_w_equal && c.loop_h_equal))
    (cases @ rand);
  (* the gadget's term for edge {0, 2}: <N, tag_1> under k_00, then k_02 *)
  let open Term in
  check "gadget term nesting"
    (Gadget.term (Aset.of_list [ Synth.atom 2; Synth.atom 0 ]) 1 (name "N")
    = enc (name "k_02") (enc (name "k_00") (pair (name "N") (name "tag_1"))))

let () =
  test_synth ();
  test_loop ();
  test_gadget ();
  Printf.printf "\n%d passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
