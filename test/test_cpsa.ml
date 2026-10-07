(* Tests of the CPSA driver: parser and replay construction on a saved CPSA output
   (data/pkinit-flawed-empty.out: pkinit-flawed at T = {}), completeness detection,
   and an integration test on pkinit-flawed and pkinit-fix2 (skipped if cpsa4 is not
   found). *)

open Trust

let failures = ref 0

let check name c =
  Printf.printf "%-64s %s\n%!" name (if c then "ok" else "FAIL");
  if not c then incr failures

let find_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = if i + m > n then None else if String.sub s i m = sub then Some i else go (i + 1) in
  go 0

let read path = In_channel.with_open_bin path In_channel.input_all
let proto_dir = "../cpsa/protocols"
let tpl name = Cpsa.load_template (Filename.concat proto_dir (name ^ ".scm"))
let ok_run out = { Cpsa.stdout = out; stderr = ""; status = Some (Unix.WEXITED 0); time = 0. }

let parser_tests () =
  let open Cpsa.Sexp in
  check "sexp: atoms, strings with ; and parens, comments"
    (parse_all "(a \"b;(c)\" ; comment\n (d e)) f"
    = [ List [ Atom "a"; Atom "\"b;(c)\""; List [ Atom "d"; Atom "e" ] ]; Atom "f" ]);
  check "sexp: printing round trip"
    (to_string (List.hd (parse_all "(x (y \"z w\") ())")) = "(x (y \"z w\") ())");
  check "sexp: unbalanced input raises"
    (match parse_all "(a (b)" with exception Failure _ -> true | _ -> false);
  let out = read "data/pkinit-flawed-empty.out" in
  let g = Cpsa.read_goal_output (ok_run out) in
  check "saved output: complete" (g.incomplete = None);
  check "saved output: 1 skeleton, 1 shape, 1 failing" (g.skeletons = 1 && g.shapes = 1
    && List.length g.failing = 1);
  check "saved output: verdict fails" (not (Cpsa.achieves_of g));
  let f = List.hd g.failing in
  check "saved output: binding is the (no ...) form"
    (to_string f.binding
    = "(no (p \"auth\" z-0 (idx 1)) (p \"auth\" \"c\" z-0 c) (p \"auth\" \"k\" z-0 k) (p \
       \"auth\" \"as\" z-0 as) (c c) (as as) (k k) (z 0))");
  let t = tpl "pkinit-flawed" in
  check "template: name, U in file order"
    (t.name = "pkinit-flawed" && List.map fst t.u = [ "non_as"; "non_c" ]);
  check "template: goal source carries the facts in id order"
    (let s = Cpsa.goal_source t (Aset.of_list [ "non_c"; "non_as" ]) in
     let i = Option.get (find_sub s "(non (privk as))")
     and j = Option.get (find_sub s "(non (privk c))") in
     i < j && find_sub s "@TRUST@" = None);
  let src = Cpsa.replay_source t f [ "non_c"; "non_as" ] in
  let sk = List.nth (parse_all src) (List.length (parse_all src) - 1) in
  check "replay: defskeleton keeps strands and uniq-orig, adds non-orig"
    (to_string sk
    = "(defskeleton pkinit-flawed (vars (tc tk tgt data) (k ak skey) (n2 n1 text) (c as t \
       name)) (defstrand client 2 (tc tc) (tk tk) (tgt tgt) (k k) (ak ak) (n2 n2) (n1 n1) (c \
       c) (t t) (as as)) (uniq-orig n2 n1) (non-orig (privk c) (privk as)))");
  (* completeness detection *)
  let inc out = (Cpsa.read_goal_output (ok_run out)).incomplete in
  let strip_nothing =
    String.concat "\n"
      (List.filter
         (fun l -> find_sub l "Nothing left" = None)
         (String.split_on_char '\n' out))
  in
  check "incomplete: no \"Nothing left to do\"" (inc strip_nothing <> None);
  check "incomplete: aborted skeleton"
    (inc (out ^ "\n(defskeleton p (vars) (label 9) (aborted))\n") <> None);
  check "incomplete: step limit message" (inc (out ^ "\n(comment \"Step limit exceeded\")\n") <> None);
  check "incomplete: stderr"
    ((Cpsa.read_goal_output { (ok_run out) with stderr = "Strand bound exceeded" }).incomplete
    <> None);
  check "incomplete: timeout"
    ((Cpsa.read_goal_output { (ok_run out) with status = None }).incomplete <> None);
  (* replay verdicts, corrected semantics *)
  let rv s = Cpsa.read_replay_output (ok_run s) in
  check "replay: realized label 0 survives"
    (Cpsa.survives (rv "(defskeleton p (vars) (label 0) (realized) (shape))"));
  check "replay: (realized) (preskeleton) does not survive"
    (rv "(defskeleton p (vars) (label 0) (realized) (preskeleton)) (defskeleton p (label 1) (realized))"
    = Cpsa.Rejected "preskeleton");
  check "replay: (realized) (dead) does not survive"
    (rv "(defskeleton p (vars) (label 0) (realized) (dead))" = Cpsa.Rejected "dead");
  check "replay: unrealized label 0 does not survive"
    (rv "(defskeleton p (vars) (label 0) (unrealized (0 1))) (defskeleton p (label 1) (realized))"
    = Cpsa.Unrealized);
  check "replay: stderr means rejected"
    (match Cpsa.read_replay_output { (ok_run "") with stderr = "bad input\n" } with
    | Cpsa.Rejected _ -> true
    | _ -> false)

let integration () =
  match Cpsa.binary () with
  | None -> print_endline "integration tests skipped: cpsa4 not found (set CPSA4)"
  | Some bin ->
      Printf.printf "integration tests with %s (%s)\n%!" bin (Cpsa.version ());
      let fam l = List.map Aset.of_list l in
      let row name ~w ~h ~asfound ~shrink =
        let t = tpl name in
        let u = Cpsa.universe t in
        let w_exh = Loop.brute_force ~u (Cpsa.verdict t) in
        check (name ^ ": exhaustive W") (Clutter.equal_family w_exh (fam w));
        List.iter
          (fun (sh, (g, r)) ->
            let cs = Cpsa.new_stats () in
            let w', h', st = Loop.weakest ~shrink:sh ~u (Cpsa.oracle ~stats:cs t) in
            check
              (Printf.sprintf "%s %s: W, H, %dg+%dr" name
                 (if sh then "shrink" else "as-found") g r)
              (Clutter.equal_family w' (fam w)
              && Clutter.equal_family h' (fam h)
              && st.distinct = g && cs.goal_runs = g && cs.replay_runs = r))
          [ (false, asfound); (true, shrink) ]
      in
      row "pkinit-flawed" ~w:[] ~h:[ [] ] ~asfound:(2, 3) ~shrink:(2, 2);
      row "pkinit-fix2" ~w:[ [ "non_as" ] ] ~h:[ [ "non_as" ] ] ~asfound:(2, 2) ~shrink:(3, 2);
      (* the replay on the saved shape, run for real *)
      let t = tpl "pkinit-flawed" in
      let f = List.hd (Cpsa.goal_run t Aset.empty).failing in
      let rep atoms = Cpsa.read_replay_output (Cpsa.run_cpsa (Cpsa.replay_source t f atoms)) in
      check "pkinit-flawed shape 0: survives non(privk c)" (rep [ "non_c" ] = Cpsa.Realized);
      check "pkinit-flawed shape 0: killed by non(privk as)"
        (not (Cpsa.survives (rep [ "non_as" ])))

let () =
  parser_tests ();
  integration ();
  if !failures > 0 then (
    Printf.printf "%d failure(s)\n" !failures;
    exit 1)
  else print_endline "test_cpsa: all checks passed"
