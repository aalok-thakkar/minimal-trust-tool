(* trust cpsa: experiments E1, E2, E4 on the CPSA rows (README.md, "Experiments").

   For every template in the protocol directory:
     E1  exhaustive lattice (all 2^|U| trusts, goal runs only) vs Loop.weakest;
     E2  distinct oracle calls, goal runs and replay runs, as-found and shrink, vs N;
     E4  wall time of Loop.weakest (as-found, shrink), exhaustive evaluation (B1),
         levelwise (B2) and greedy (B3): 1 warm-up, then [reps] repetitions.
   Writes <out>/cpsa_rows.csv, cpsa_timing.csv, cpsa_timing_summary.csv, cpsa_log.txt,
   manifest_cpsa.txt. *)

open Trust

let fam_str f =
  if f = [] then "[]"
  else String.concat ";" (List.map (fun s -> "{" ^ String.concat " " (Aset.elements s) ^ "}") f)

let set_str s = "{" ^ String.concat " " (Aset.elements s) ^ "}"
let b2s b = if b then "yes" else "no"

let csv_field s =
  if String.exists (fun c -> c = ',' || c = '"' || c = '\n') s then
    "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""
  else s

let csv_line oc l = output_string oc (String.concat "," (List.map csv_field l) ^ "\n")

let shell cmd =
  try
    let ic = Unix.open_process_in (cmd ^ " 2>/dev/null") in
    let s = In_channel.input_all ic in
    ignore (Unix.close_process_in ic);
    String.trim s
  with _ -> ""

let now_iso () =
  let t = Unix.gettimeofday () in
  let tm = Unix.localtime t in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

let quantile sorted p =
  let n = Array.length sorted in
  if n = 0 then nan
  else
    let x = p *. float (n - 1) in
    let i = int_of_float (floor x) in
    let j = min (i + 1) (n - 1) in
    sorted.(i) +. ((x -. float i) *. (sorted.(j) -. sorted.(i)))

let all_subsets u =
  List.fold_left
    (fun acc a -> acc @ List.map (fun s -> Aset.add a s) acc)
    [ Aset.empty ] (Aset.elements u)

(* ---- one row: E1 and E2 ---- *)

type mode_result = {
  w : Aset.t list;
  h : Aset.t list;
  st : Loop.stats;
  cs : Cpsa.stats;
  wall : float;
}

let run_mode ?timeout ~shrink tpl =
  let cs = Cpsa.new_stats () in
  let t0 = Unix.gettimeofday () in
  let w, h, st = Loop.weakest ~shrink ~u:(Cpsa.universe tpl) (Cpsa.oracle ?timeout ~stats:cs tpl) in
  { w; h; st; cs; wall = Unix.gettimeofday () -. t0 }

let row_header =
  [ "row"; "n_U"; "U"; "points"; "monotone"; "W_exh"; "A_exh"; "n_W"; "n_A"; "N";
    "lattice_cpsa_s"; "lattice_max_run_s" ]
  @ List.concat_map
      (fun m ->
        List.map (fun c -> m ^ "_" ^ c)
          [ "W"; "H"; "agrees"; "H_eq_A"; "distinct"; "queries"; "shrink_calls"; "goal_runs";
            "replay_runs"; "rejected"; "ill_formed"; "distinct_le_N"; "cpsa_s"; "wall_s" ])
      [ "asfound"; "shrink" ]
  @ [ "b2_found_eq_W"; "b2_calls"; "b3_answer"; "b3_in_W"; "b3_calls"; "error" ]

let n_cols = List.length row_header

let fmt_f x = Printf.sprintf "%.4f" x

let e1_e2 ?timeout log tpl =
  let u = Cpsa.universe tpl in
  let name = tpl.Cpsa.name in
  log (Printf.sprintf "=== %s  U = %s" name (set_str u));
  (* E1 *)
  let cs = Cpsa.new_stats () in
  let tbl = Hashtbl.create 64 in
  let maxrun = ref 0. in
  let w_exh =
    Loop.brute_force ~u (fun t ->
        let before = cs.goal_time in
        let v = Cpsa.verdict ?timeout ~stats:cs tpl t in
        maxrun := Float.max !maxrun (cs.goal_time -. before);
        Hashtbl.replace tbl t v;
        log (Printf.sprintf "  lattice %s: %s" (set_str t) (if v then "achieves" else "fails"));
        v)
  in
  let pts = all_subsets u in
  let monotone =
    List.for_all
      (fun s ->
        (not (Hashtbl.find tbl s))
        || List.for_all (fun t -> (not (Aset.subset s t)) || Hashtbl.find tbl t) pts)
      pts
  in
  let a_exh = Clutter.blocker w_exh in
  let n = List.length w_exh + List.length a_exh in
  log
    (Printf.sprintf "  exhaustive: W = %s, A = %s, monotone = %b, %d goal runs, %.3f s"
       (fam_str w_exh) (fam_str a_exh) monotone cs.goal_runs cs.goal_time);
  (* E2 *)
  let modes =
    List.map
      (fun shrink ->
        let r = run_mode ?timeout ~shrink tpl in
        List.iter (fun l -> log ("    " ^ l)) (List.rev r.cs.log);
        log
          (Printf.sprintf "  weakest[%s]: W = %s, H = %s, distinct %d (%dg+%dr), rejected %d"
             (if shrink then "shrink" else "as-found")
             (fam_str r.w) (fam_str r.h) r.st.distinct r.cs.goal_runs r.cs.replay_runs
             r.cs.rejected);
        r)
      [ false; true ]
  in
  (* B2, B3 (calls are deterministic; timed again in E4) *)
  let pred t = Cpsa.verdict ?timeout tpl t in
  let b2 = Loop.levelwise ~u pred in
  let b3, b3_calls = Loop.greedy_rgl ~u pred in
  let b3_in_w = match b3 with Some s -> List.exists (Aset.equal s) w_exh | None -> w_exh = [] in
  let mode_cols r =
    [ fam_str r.w; fam_str r.h; b2s (Clutter.equal_family r.w w_exh);
      b2s (Clutter.equal_family r.h a_exh); string_of_int r.st.distinct;
      string_of_int r.st.queries; string_of_int r.st.shrink_calls;
      string_of_int r.cs.goal_runs; string_of_int r.cs.replay_runs;
      string_of_int r.cs.rejected; string_of_int r.cs.ill_formed;
      b2s (r.st.distinct <= n); fmt_f (Cpsa.cpsa_time r.cs); fmt_f r.wall ]
  in
  [ name; string_of_int (Aset.cardinal u); String.concat " " (List.map fst tpl.Cpsa.u);
    string_of_int (List.length pts); b2s monotone; fam_str w_exh; fam_str a_exh;
    string_of_int (List.length w_exh); string_of_int (List.length a_exh); string_of_int n;
    fmt_f cs.goal_time; fmt_f !maxrun ]
  @ List.concat_map mode_cols modes
  @ [ b2s (b2.complete && Clutter.equal_family b2.found w_exh); string_of_int b2.calls;
      (match b3 with Some s -> set_str s | None -> "none"); b2s b3_in_w;
      string_of_int b3_calls; "" ]

(* ---- E4 ---- *)

let methods ?timeout tpl =
  let u = Cpsa.universe tpl in
  let pred cs t = Cpsa.verdict ?timeout ~stats:cs tpl t in
  [ ("weakest", fun cs -> ignore (Loop.weakest ~u (Cpsa.oracle ?timeout ~stats:cs tpl)));
    ("weakest_shrink",
      fun cs -> ignore (Loop.weakest ~shrink:true ~u (Cpsa.oracle ?timeout ~stats:cs tpl)));
    ("exhaustive_B1", fun cs -> ignore (Loop.brute_force ~u (pred cs)));
    ("levelwise_B2", fun cs -> ignore (Loop.levelwise ~u (pred cs)));
    ("greedy_B3", fun cs -> ignore (Loop.greedy_rgl ~u (pred cs))) ]

let e4 ?timeout ~reps tpl raw summary =
  let ms = methods ?timeout tpl in
  let once f =
    let cs = Cpsa.new_stats () in
    let t0 = Unix.gettimeofday () in
    f cs;
    (Unix.gettimeofday () -. t0, cs)
  in
  List.iter (fun (_, f) -> ignore (once f)) ms;
  (* warm-up *)
  let samples = Hashtbl.create 8 in
  for rep = 1 to reps do
    List.iter
      (fun (m, f) ->
        let wall, cs = once f in
        let cpsa = Cpsa.cpsa_time cs in
        csv_line raw
          [ tpl.Cpsa.name; m; string_of_int rep; fmt_f wall; fmt_f cpsa;
            Printf.sprintf "%.3f" (cpsa /. wall); string_of_int cs.goal_runs;
            string_of_int cs.replay_runs ];
        Hashtbl.replace samples m
          ((wall, cpsa /. wall, cs.goal_runs, cs.replay_runs)
          :: Option.value (Hashtbl.find_opt samples m) ~default:[]))
      ms
  done;
  flush raw;
  List.iter
    (fun (m, _) ->
      let l = Hashtbl.find samples m in
      let walls = Array.of_list (List.map (fun (w, _, _, _) -> w) l) in
      let shares = Array.of_list (List.map (fun (_, s, _, _) -> s) l) in
      Array.sort compare walls;
      Array.sort compare shares;
      let _, _, g, r = List.hd l in
      let q1 = quantile walls 0.25 and q3 = quantile walls 0.75 in
      csv_line summary
        [ tpl.Cpsa.name; m; string_of_int reps; fmt_f (quantile walls 0.5); fmt_f q1; fmt_f q3;
          fmt_f (q3 -. q1); Printf.sprintf "%.3f" (quantile shares 0.5); string_of_int g;
          string_of_int r ])
    ms;
  flush summary

(* ---- main ---- *)

let usage () =
  prerr_endline
    "usage: trust cpsa [--protocols DIR] [--out DIR] [--only NAME,...] [--reps N] \
     [--no-timing] [--timeout SECONDS]";
  exit 2

let main args =
  let protocols = ref "cpsa/protocols" and out = ref "results" and only = ref [] in
  let reps = ref 5 and timing = ref true and timeout = ref 600. in
  let rec parse = function
    | [] -> ()
    | "--protocols" :: d :: r -> protocols := d; parse r
    | "--out" :: d :: r -> out := d; parse r
    | "--only" :: l :: r -> only := String.split_on_char ',' l; parse r
    | "--reps" :: n :: r -> reps := int_of_string n; parse r
    | "--no-timing" :: r -> timing := false; parse r
    | "--timeout" :: s :: r -> timeout := float_of_string s; parse r
    | _ -> usage ()
  in
  parse args;
  let timeout = !timeout in
  (match Cpsa.binary () with
  | None -> prerr_endline "trust cpsa: cpsa4 not found (set CPSA4)"; exit 1
  | Some _ -> ());
  let files =
    Cpsa.templates_in !protocols
    |> List.filter (fun f ->
           !only = [] || List.mem (Filename.remove_extension (Filename.basename f)) !only)
  in
  if not (Sys.file_exists !out) then Sys.mkdir !out 0o755;
  let path f = Filename.concat !out f in
  let load_start = shell "uptime" and date_start = now_iso () in
  let logc = open_out (path "cpsa_log.txt") in
  let log s = print_endline s; output_string logc (s ^ "\n"); flush logc in
  let rows = open_out (path "cpsa_rows.csv") in
  csv_line rows row_header;
  let raw = if !timing then Some (open_out (path "cpsa_timing.csv")) else None in
  let summary = if !timing then Some (open_out (path "cpsa_timing_summary.csv")) else None in
  Option.iter
    (fun oc ->
      csv_line oc
        [ "row"; "method"; "rep"; "wall_s"; "cpsa_s"; "cpsa_share"; "goal_runs"; "replay_runs" ])
    raw;
  Option.iter
    (fun oc ->
      csv_line oc
        [ "row"; "method"; "reps"; "wall_median_s"; "wall_q1_s"; "wall_q3_s"; "wall_iqr_s";
          "cpsa_share_median"; "goal_runs"; "replay_runs" ])
    summary;
  let errors = ref [] in
  let tpls = List.map Cpsa.load_template files in
  (* E1, E2 for every row first, then E4 for every row *)
  List.iter
    (fun tpl ->
      let cols =
        try e1_e2 ~timeout log tpl
        with (Cpsa.Cpsa_error m | Failure m | Loop.Unsound_witness m) as e ->
          let m = Printexc.to_string e ^ ": " ^ m in
          log ("  ERROR " ^ m);
          errors := (tpl.Cpsa.name, m) :: !errors;
          [ tpl.Cpsa.name ] @ List.init (n_cols - 2) (fun _ -> "") @ [ m ]
      in
      csv_line rows cols;
      flush rows)
    tpls;
  close_out rows;
  (match (raw, summary) with
  | Some raw, Some summary ->
      List.iter
        (fun tpl ->
          if not (List.mem_assoc tpl.Cpsa.name !errors) then (
            log (Printf.sprintf "=== E4 %s (1 warm-up + %d reps)" tpl.Cpsa.name !reps);
            try e4 ~timeout ~reps:!reps tpl raw summary
            with Cpsa.Cpsa_error m ->
              log ("  ERROR " ^ m);
              errors := (tpl.Cpsa.name ^ " (E4)", m) :: !errors))
        tpls;
      close_out raw;
      close_out summary
  | _ -> ());
  close_out logc;
  let load_end = shell "uptime" and date_end = now_iso () in
  let m = open_out (path "manifest_cpsa.txt") in
  let p fmt = Printf.fprintf m (fmt ^^ "\n") in
  p "trust cpsa: experiments E1, E2, E4";
  p "command: %s" (String.concat " " (Array.to_list Sys.argv));
  p "cwd: %s" (Sys.getcwd ());
  p "start: %s" date_start;
  p "end: %s" date_end;
  p "load at start (uptime): %s" load_start;
  p "load at end (uptime): %s" load_end;
  p "note: runs are sequential; other jobs on the machine are not controlled, see load";
  p "CPSA: %s (%s), no options (step limit 2000, strand bound 12)" (Cpsa.version ())
    (Option.get (Cpsa.binary ()));
  p "OCaml: %s" Sys.ocaml_version;
  p "dune: %s" (shell "dune --version");
  p "machine: %s, %s cores, %s bytes memory" (shell "sysctl -n machdep.cpu.brand_string")
    (shell "sysctl -n hw.ncpu") (shell "sysctl -n hw.memsize");
  p "OS: %s" (String.concat " " (String.split_on_char '\n' (shell "sw_vers")));
  p "timeout per CPSA run: %.0f s; E4: 1 warm-up, %d repetitions (median, IQR)" timeout !reps;
  p "replay check: corrected (label 0 realized, no (preskeleton), no (dead))";
  p "executable md5: %s" (try Digest.to_hex (Digest.file Sys.executable_name) with _ -> "?");
  p "templates (%d):" (List.length tpls);
  List.iter
    (fun t -> p "  %s  %s  md5 %s" t.Cpsa.name t.Cpsa.path (Digest.to_hex (Digest.file t.Cpsa.path)))
    tpls;
  p "errors: %s"
    (if !errors = [] then "none"
     else String.concat "; " (List.rev_map (fun (n, e) -> n ^ ": " ^ e) !errors));
  close_out m;
  if !errors <> [] then exit 1
