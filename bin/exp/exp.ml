(* trust-exp: experiments over the bounded analyser.
     trust-exp rows      [--reps N]               E1/E2: analyser rows, witness modes
     trust-exp channels                           E6: NSPK/NSL with channel generators
     trust-exp compose                            E7: composition pairs
     trust-exp bound     [--timeout S] [--max-instances K]   E5: pool sensitivity
   Common: --out DIR (default results). Each writes DIR/<exp>.csv and prints a table. *)

open Trust
module P = Protocols

let now = Unix.gettimeofday
let out_dir = ref "results"
let reps = ref 5
let timeout = ref 600.  (* seconds per run of Algorithm 1 (bound; channels at 2 instances) *)
let max_instances = ref 3

(* ---- formatting ------------------------------------------------------------------ *)

let fam_str = function
  | [] -> "false"
  | f -> String.concat "; " (List.map Aset.to_string f)

let clutter_str = function
  | [ s ] when Aset.is_empty s -> "{{}}"
  | f -> fam_str f

let mode_str = function
  | Bounded.As_found -> "as_found"
  | Bounded.Pruned -> "pruned"
  | Bounded.Least -> "least"

let csv_field s =
  if String.exists (fun c -> c = ',' || c = '"' || c = '\n') s then
    "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""
  else s

let write_csv name header rows =
  (try Sys.mkdir !out_dir 0o755 with Sys_error _ -> ());
  let path = Filename.concat !out_dir (name ^ ".csv") in
  let oc = open_out path in
  output_string oc (String.concat "," header ^ "\n");
  List.iter (fun r -> output_string oc (String.concat "," (List.map csv_field r) ^ "\n")) rows;
  close_out oc;
  Printf.printf "wrote %s (%d rows)\n%!" path (List.length rows)

let b = string_of_bool
let i = string_of_int
let f3 x = Printf.sprintf "%.4f" x

let median_iqr xs =
  let a = Array.of_list (List.sort compare xs) in
  let n = Array.length a in
  let q p =
    let x = p *. float (n - 1) in
    let lo = int_of_float (floor x) in
    let hi = min (n - 1) (lo + 1) in
    a.(lo) +. ((x -. float lo) *. (a.(hi) -. a.(lo)))
  in
  (q 0.5, q 0.75 -. q 0.25)

(* ---- one run of Algorithm 1 ------------------------------------------------------ *)

type lrun = {
  w : Aset.t list;
  h : Aset.t list;
  st : Loop.stats;
  ctr : Bounded.counter;
  time : float;
}

let run_loop ?deadline ?reduce ?key_stops ?pool ~shrink row mode =
  let ctr = Bounded.counter () in
  let t0 = now () in
  let w, h, st =
    Loop.weakest ~shrink ~u:row.P.u
      (P.oracle ?deadline ?reduce ?key_stops ~counter:ctr ?pool row mode)
  in
  { w; h; st; ctr; time = now () -. t0 }

let brute ?pool row =
  let o = P.oracle ?pool row Bounded.As_found in
  Loop.brute_force ~u:row.P.u (fun t -> o t = Loop.Achieves)

(* non-principal attack states over the whole lattice (channels.py's STATS) *)
let nonprincipal_all row =
  let m = row.P.model row.P.default_pool in
  let atoms = Aset.elements row.P.u in
  let n = List.length atoms in
  let total = ref 0 in
  for mask = 0 to (1 lsl n) - 1 do
    let t = Aset.of_list (List.filteri (fun j _ -> mask land (1 lsl j) <> 0) atoms) in
    let r = Bounded.search ~check_lattice:true m ~u:row.P.u Bounded.Least t in
    total := !total + r.nonprincipal
  done;
  !total

let expected_match row w =
  match row.P.expected with
  | None -> "n/a"
  | Some e -> b (Clutter.equal_family e w)

(* ---- E1/E2: rows ------------------------------------------------------------------ *)

let rows () =
  let modes = [ (Bounded.As_found, false); (Bounded.As_found, true); (Bounded.Pruned, false);
                (Bounded.Pruned, true); (Bounded.Least, false); (Bounded.Least, true) ] in
  let out = ref [] in
  Printf.printf "%-18s %-9s %-6s %-44s %-30s %5s %5s %5s %6s %8s %6s %10s\n" "row" "mode"
    "shrink" "W" "H" "calls" "query" "shr" "|H|+|W|" "states" "brute" "time(s)";
  List.iter
    (fun row ->
      let bf = brute row in
      List.iter
        (fun (mode, shrink) ->
          let runs = List.init !reps (fun _ -> run_loop ~shrink row mode) in
          let r = List.hd runs in
          let med, iqr = median_iqr (List.map (fun r -> r.time) runs) in
          let nmin = List.length r.h + List.length r.w in
          let agree = Clutter.equal_family bf r.w in
          let is_ref = mode = row.P.reference_mode && not shrink in
          Printf.printf "%-18s %-9s %-6b %-44s %-30s %5d %5d %5d %6d %8d %6b %10.4f%s\n"
            row.P.title (mode_str mode) shrink (fam_str r.w) (clutter_str r.h) r.st.distinct
            r.st.queries r.st.shrink_calls nmin r.ctr.states agree med
            (if is_ref then "  (Python reference mode)" else "");
          out :=
            [ row.P.id; Aset.to_string row.P.u; mode_str mode; b shrink; fam_str r.w;
              clutter_str r.h; i r.st.distinct; i r.st.queries; i r.st.shrink_calls; i nmin;
              b (r.st.distinct <= nmin); i r.ctr.states; i r.ctr.max_states;
              i r.ctr.nonprincipal; b agree; expected_match row r.w; b is_ref; f3 med; f3 iqr;
              i !reps ]
            :: !out)
        modes)
    P.analyser_rows;
  write_csv "rows"
    [ "row"; "U"; "witness_mode"; "shrink"; "W"; "H"; "distinct_calls"; "loop_queries";
      "shrink_calls"; "H_plus_W"; "calls_within_H_plus_W"; "states_explored";
      "max_states_one_call"; "nonprincipal_witnesses"; "brute_force_agrees";
      "W_matches_paper"; "python_reference_mode"; "time_median_s"; "time_iqr_s"; "reps" ]
    (List.rev !out);
  (* Table 1: the first witness of the signed CR as found *)
  let m = P.signed_cr.model P.signed_cr.default_pool in
  let r = Bounded.search ~key_stops:true m ~u:P.signed_cr.u Bounded.As_found Aset.empty in
  match r.outcome with
  | Bounded.Attack { run; stops } ->
      Format.printf "signed CR, empty trust, first witness as found: stops = %a@.  %a@." Aset.pp
        stops (Bounded.pp_run m) run;
      let pr = Bounded.prune m ~u:P.signed_cr.u Aset.empty run in
      Format.printf "  pruned: stops = %a@.  %a@." Aset.pp
        (Bounded.stops m ~u:P.signed_cr.u Aset.empty pr)
        (Bounded.pp_run m) pr
  | Bounded.Achieves -> print_endline "signed CR: empty trust achieves (unexpected)"

(* ---- E6: channels ---------------------------------------------------------------- *)

let channels () =
  let rows =
    [ P.nspk; P.nsl; P.nspk_keys_least; P.nsl_keys_least; P.nspk_channels; P.nsl_channels;
      P.nspk_channels_hijack; P.nsl_channels_hijack ]
  in
  let out = ref [] in
  List.iter
    (fun row ->
      let mode = row.P.reference_mode in
      let r = run_loop ~shrink:false row mode in
      let bf = brute row in
      let np = nonprincipal_all row in
      (* the same row with two instances per role (reduced search, pruned witnesses) *)
      let w2 =
        try
          let r2 =
            run_loop ~deadline:(now () +. !timeout) ~reduce:true ~key_stops:false
              ~pool:{ row.P.default_pool with P.instances = 2 } ~shrink:false row Bounded.Pruned
          in
          Some r2
        with Bounded.Timeout -> None
      in
      let m = row.P.model row.P.default_pool in
      let keys = Aset.of_list [ "Non(sk_A)"; "Non(sk_B)" ] in
      let wit =
        match (Bounded.search m ~u:row.P.u mode keys).outcome with
        | Bounded.Achieves -> "achieves"
        | Bounded.Attack { run; stops } ->
            Format.asprintf "stops %a: %a" Aset.pp stops (Bounded.pp_run m) run
      in
      Printf.printf "== %s (%s witnesses)\n   U = %s\n   H = %s\n   W = %s\n" row.P.title
        (mode_str mode) (Aset.to_string row.P.u) (clutter_str r.h) (fam_str r.w);
      Printf.printf
        "   calls: %d distinct, %d queries; brute force over 2^%d agrees: %b; non-principal \
         attack states over the lattice: %d; time %.3fs\n"
        r.st.distinct r.st.queries (Aset.cardinal row.P.u) (Clutter.equal_family bf r.w) np
        r.time;
      Printf.printf "   under {Non(sk_A), Non(sk_B)}: %s\n" wit;
      (match w2 with
      | Some r2 ->
          Printf.printf "   2 instances per role: W = %s (%s), %d calls, %d states, %.1fs\n\n"
            (fam_str r2.w)
            (if Clutter.equal_family r2.w r.w then "unchanged" else "CHANGED")
            r2.st.distinct r2.ctr.states r2.time
      | None -> Printf.printf "   2 instances per role: timeout after %.0fs\n\n" !timeout);
      out :=
        [ row.P.id; Aset.to_string row.P.u; mode_str mode;
          b (row.P.model row.P.default_pool).Bounded.hijack; fam_str r.w; clutter_str r.h;
          i r.st.distinct; i r.st.queries; b (Clutter.equal_family bf r.w); i np;
          expected_match row r.w; f3 r.time;
          (match w2 with Some r2 -> fam_str r2.w | None -> "timeout");
          (match w2 with
          | Some r2 -> b (not (Clutter.equal_family r2.w r.w))
          | None -> "");
          (match w2 with Some r2 -> i r2.ctr.states | None -> "") ]
        :: !out)
    rows;
  write_csv "channels"
    [ "row"; "U"; "witness_mode"; "hijack"; "W"; "H"; "distinct_calls"; "loop_queries";
      "brute_force_agrees"; "nonprincipal_attack_states"; "W_matches_paper"; "time_s";
      "W_2_instances"; "W_changed_at_2_instances"; "states_2_instances" ]
    (List.rev !out)

(* ---- E7: composition --------------------------------------------------------------- *)

let compose () =
  let out = ref [] in
  let contains_member e f = List.exists (fun x -> Aset.subset x e) f in
  List.iter
    (fun v ->
      let go part goals =
        let row = P.composition v part goals in
        let r = run_loop ~shrink:false row Bounded.Least in
        let bf = brute row in
        (row, r, Clutter.equal_family bf r.w)
      in
      let (_, r1, a1) = go P.P1 P.Chi1 and (_, r2, a2) = go P.P2 P.Chi2 in
      let (_, rc1, ac1) = go P.Both P.Chi1 and (_, rc2, ac2) = go P.Both P.Chi2 in
      let (row, rc, ac) = go P.Both P.Chi1_and_chi2 in
      let join a b' = Clutter.minimalize (List.concat_map (fun x -> List.map (Aset.union x) b') a) in
      let j = join r1.w r2.w in
      let union = Clutter.minimalize (r1.h @ r2.h) in
      let bad = List.filter (fun e -> not (contains_member e union)) rc.h in
      let cross1 = List.filter (fun e -> not (contains_member e r1.h)) rc1.h in
      let cross2 = List.filter (fun e -> not (contains_member e r2.h)) rc2.h in
      let exact = Clutter.equal_family j rc.w in
      let cor = Clutter.equal_family (join rc1.w rc2.w) rc.w in
      let name = P.variant_name v in
      Printf.printf "== %s, U = %s\n" name (Aset.to_string row.P.u);
      let line l r = Printf.printf "   %-24s W = %-46s H = %-40s calls %d (queries %d)\n" l
          (fam_str r.w) (clutter_str r.h) r.st.distinct r.st.queries in
      line "P1 alone, chi1" r1;
      line "P2 alone, chi2" r2;
      Printf.printf "   %-24s     %s\n" "join" (fam_str j);
      line "P1||P2, chi1" rc1;
      line "P1||P2, chi2" rc2;
      line "P1||P2, chi1 & chi2" rc;
      Printf.printf
        "   Corollary (W(chi1) v W(chi2) = W(chi1 & chi2) in composition): %b\n\
        \   Theorem condition: %s; W(composition) = join: %b\n\
        \   cross-protocol stopping sets: chi1 %s; chi2 %s\n\
        \   brute force agrees on all five: %b\n\n"
        cor
        (if bad = [] then "holds" else "fails, offending " ^ clutter_str bad)
        exact
        (if cross1 = [] then "none" else clutter_str cross1)
        (if cross2 = [] then "none" else clutter_str cross2)
        (a1 && a2 && ac1 && ac2 && ac);
      out :=
        [ name; Aset.to_string row.P.u; fam_str r1.w; i r1.st.distinct; i r1.st.queries;
          fam_str r2.w; i r2.st.distinct; i r2.st.queries; fam_str j; fam_str rc1.w;
          clutter_str rc1.h; fam_str rc2.w; clutter_str rc2.h; fam_str rc.w; clutter_str rc.h;
          i rc.st.distinct; i rc.st.queries; b exact; b (bad = []);
          (if cross1 = [] then "none" else clutter_str cross1);
          (if cross2 = [] then "none" else clutter_str cross2); b cor;
          b (a1 && a2 && ac1 && ac2 && ac) ]
        :: !out)
    [ P.Tagged; P.Untagged; P.Separate_keys ];
  write_csv "compose"
    [ "variant"; "U"; "W_P1_chi1"; "calls_P1"; "queries_P1"; "W_P2_chi2"; "calls_P2";
      "queries_P2"; "join"; "W_comp_chi1"; "H_comp_chi1"; "W_comp_chi2"; "H_comp_chi2";
      "W_comp"; "H_comp"; "calls_comp"; "queries_comp"; "W_comp_equals_join";
      "theorem_condition_holds"; "cross_protocol_chi1"; "cross_protocol_chi2";
      "corollary_holds"; "brute_force_agrees" ]
    (List.rev !out)

(* ---- E5: bound sensitivity ---------------------------------------------------------- *)

let bound () =
  let out = ref [] in
  Printf.printf "%-18s %-9s %4s %-7s %-8s %-44s %6s %10s %10s %9s %s\n" "row" "mode" "inst"
    "earlier" "status" "W" "calls" "states" "max_states" "time(s)" "W changed";
  List.iter
    (fun row ->
      let mode = Bounded.Pruned in
      let base = ref None in
      List.iter
        (fun earlier ->
          let stop = ref false in
          for k = 1 to !max_instances do
            if not !stop then begin
              let pool = { P.instances = k; earlier } in
              let deadline = now () +. !timeout in
              let t0 = now () in
              let res =
                try
                  let r =
                    run_loop ~deadline ~reduce:true ~key_stops:false ~pool ~shrink:false row mode
                  in
                  Ok r
                with Bounded.Timeout -> Error (now () -. t0)
              in
              let is_default = k = 1 && earlier = row.P.default_pool.earlier in
              match res with
              | Ok r ->
                  if is_default then base := Some r.w;
                  let changed =
                    match !base with
                    | Some bw when not is_default -> b (not (Clutter.equal_family bw r.w))
                    | Some _ -> "reference"
                    | None -> "n/a"
                  in
                  Printf.printf "%-18s %-9s %4d %-7b %-8s %-44s %6d %10d %10d %9.3f %s\n%!"
                    row.P.title (mode_str mode) k earlier "ok" (fam_str r.w) r.st.distinct
                    r.ctr.states r.ctr.max_states r.time changed;
                  out :=
                    [ row.P.id; mode_str mode; i k; b earlier; "ok"; fam_str r.w;
                      clutter_str r.h; i r.st.distinct; i r.ctr.states; i r.ctr.max_states;
                      f3 r.time; changed; b is_default ]
                    :: !out
              | Error dt ->
                  stop := true;
                  Printf.printf "%-18s %-9s %4d %-7b %-8s %-44s %6s %10s %10s %9.3f %s\n%!"
                    row.P.title (mode_str mode) k earlier "timeout" "-" "-" "-" "-" dt "-";
                  out :=
                    [ row.P.id; mode_str mode; i k; b earlier; "timeout"; ""; ""; ""; ""; "";
                      f3 dt; ""; b is_default ]
                    :: !out
            end
          done)
        (* the default pool first, so later runs compare against it *)
        (if row.P.default_pool.earlier then [ true; false ] else [ false; true ]))
    P.analyser_rows;
  write_csv "bound"
    [ "row"; "witness_mode"; "instances_per_role"; "earlier_session"; "status"; "W"; "H";
      "distinct_calls"; "states_explored"; "max_states_one_call"; "time_s";
      "W_changed_vs_default_pool"; "default_pool" ]
    (List.rev !out)

(* print the witness of one oracle call *)
let witness id k earlier atoms =
  let rows =
    [ P.signed_cr; P.two_key; P.signed_nonames; P.shared_nonames; P.nspk; P.nsl;
      P.nspk_channels; P.nsl_channels; P.nspk_channels_hijack; P.nsl_channels_hijack ]
  in
  match List.find_opt (fun r -> r.P.id = id) rows with
  | None -> prerr_endline ("unknown row " ^ id); exit 2
  | Some row ->
      let m = row.P.model { P.instances = k; earlier } in
      let t = Aset.of_list atoms in
      let r = Bounded.search ~reduce:true ~key_stops:false m ~u:row.P.u Bounded.Pruned t in
      Printf.printf "%s, %d instances, earlier %b, trust %s: %d states\n" id k earlier
        (Aset.to_string t) r.states;
      (match r.outcome with
      | Bounded.Achieves -> print_endline "achieves"
      | Bounded.Attack { run; stops } ->
          Format.printf "stops %a@." Aset.pp stops;
          List.iter
            (fun (e : Bounded.event) ->
              Format.printf "  %-14s %a@." m.Bounded.strands.(e.strand).Bounded.label
                Bounded.pp_event e)
            run.Bounded.events)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let rec opts = function
    | "--out" :: d :: r -> out_dir := d; opts r
    | "--reps" :: n :: r -> reps := int_of_string n; opts r
    | "--timeout" :: s :: r -> timeout := float_of_string s; opts r
    | "--max-instances" :: k :: r -> max_instances := int_of_string k; opts r
    | x :: r -> x :: opts r
    | [] -> []
  in
  match opts args with
  | [ "rows" ] -> rows ()
  | [ "channels" ] -> channels ()
  | [ "compose" ] -> compose ()
  | [ "bound" ] -> bound ()
  | "witness" :: id :: k :: e :: atoms ->
      witness id (int_of_string k) (bool_of_string e) atoms
  | _ ->
      prerr_endline
        "usage: trust-exp (rows|channels|compose|bound) [--out DIR] [--reps N] [--timeout S] \
         [--max-instances K]";
      exit 2
