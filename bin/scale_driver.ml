(* trust scale: the synthetic scalability study (experiment E3) and the gadget
   validity check (README.md, "Experiments").

   Phases (default: all, in this order):
     counts   every (instance, method) job in a forked child with a hard timeout
              (SIGKILL from the parent) and a heap cap; up to --jobs children at once.
              Call counts are deterministic, so one run each. -> scale_counts.csv
     gadget   Appendix-A gadget oracle vs hypergraph oracle on every trust, one
              instance at a time.                                -> gadget_check.csv
     timing   Algorithm 1 (minimal witnesses) re-run sequentially, one child at a
              time, with repetitions; median and IQR.             -> scale_timing.csv
   plus results/manifest_scale.txt. *)

open Trust

(* ---- configuration ---------------------------------------------------------- *)

type config = {
  quick : bool;
  out : string;
  jobs : int;
  timeout : float;
  mem_cap_mb : int;
  seeds : int list;
  rand_ns : int list;
  pair_ns : int list;
  thr_ns : int list;
  b1_max : int;
  b2_budget : int;
  gadget_seeds : int list;
  pad_extra : int;  (** extra atoms per padded witness *)
}

let full_config out jobs =
  {
    quick = false;
    out;
    jobs;
    timeout = 600.;
    mem_cap_mb = 3000;
    seeds = List.init 10 Fun.id;
    rand_ns = List.init 16 (fun i -> 5 * (i + 1));
    pair_ns = List.init 11 (fun i -> 4 + (2 * i));
    thr_ns = List.init 9 (fun i -> 4 + (2 * i));
    b1_max = 24;
    b2_budget = 1 lsl 21;
    gadget_seeds = List.init 8 Fun.id;
    pad_extra = 2;
  }

let quick_config out jobs =
  {
    quick = true;
    out;
    jobs;
    timeout = 20.;
    mem_cap_mb = 2000;
    seeds = [ 0; 1; 2 ];
    rand_ns = [ 5; 10; 15; 20 ];
    pair_ns = [ 4; 6; 8; 10; 12 ];
    thr_ns = [ 4; 6; 8 ];
    b1_max = 16;
    b2_budget = 1 lsl 21;
    gadget_seeds = [ 0 ];
    pad_extra = 2;
  }

(* ---- instances and jobs ----------------------------------------------------- *)

type inst = { family : string; n : int; m : int; seed : int }
type meth = Alg1 | Padded | Padded_shrink | B1 | B2 | B3

let meth_name = function
  | Alg1 -> "alg1"
  | Padded -> "padded"
  | Padded_shrink -> "padded_shrink"
  | B1 -> "b1"
  | B2 -> "b2"
  | B3 -> "b3"

let random_families = [ ("rand-m1", 1); ("rand-m2", 2); ("rand-m4", 4) ]

let build i =
  match List.assoc_opt i.family random_families with
  | Some _ ->
      Synth.random
        (Synth.random_state ~family:i.family ~n:i.n ~m:i.m ~seed:i.seed)
        ~n:i.n ~m:i.m
  | None -> (
      match i.family with
      | "pairs" -> Synth.disjoint_pairs i.n
      | "dual" -> Synth.dual_pairs i.n
      | "thr" -> Synth.threshold ~s:i.n ~k:(i.n / 2)
      | "thr-dual" -> Synth.threshold ~s:i.n ~k:((i.n / 2) + 1)
      | f -> invalid_arg ("unknown family " ^ f))

let instances cfg =
  let rand =
    List.concat_map
      (fun (f, mult) ->
        List.concat_map
          (fun n -> List.map (fun seed -> { family = f; n; m = mult * n; seed }) cfg.seeds)
          cfg.rand_ns)
      random_families
  in
  let det f ns = List.map (fun n -> { family = f; n; m = 0; seed = 0 }) ns in
  rand @ det "pairs" cfg.pair_ns @ det "dual" cfg.pair_ns @ det "thr" cfg.thr_ns
  @ det "thr-dual" cfg.thr_ns

let methods cfg i =
  [ Alg1; Padded; Padded_shrink ]
  @ (if i.n <= cfg.b1_max then [ B1 ] else [])
  @ [ B2; B3 ]

(* ---- one run ---------------------------------------------------------------- *)

let counts_header =
  "family,n,m,seed,method,status,H,W,calls,queries,shrink_calls,iterations,bound,\
   within_bound,equals_bound,h_recovered,complete,in_W,oracle_time,blocker_time,wall,\
   peak_heap_mb,w_digest"

let digest fam =
  String.sub
    (Digest.to_hex (Digest.string (String.concat ";" (List.map Aset.to_string (Clutter.sort fam)))))
    0 12

let peak_heap_mb () =
  let s = Gc.quick_stat () in
  float_of_int (s.top_heap_words * (Sys.word_size / 8)) /. 1048576.

let b2s b = if b then "1" else "0"
let f6 x = Printf.sprintf "%.6f" x

let row i meth ~status ~h ?(w = "") ?(calls = "") ?(queries = "") ?(shrink = "")
    ?(iters = "") ?(bound = "") ?(within = "") ?(equals = "") ?(hrec = "")
    ?(complete = "") ?(in_w = "") ?(ot = "") ?(bt = "") ?(wall = "") ?(peak = "")
    ?(dg = "") () =
  String.concat ","
    [
      i.family; string_of_int i.n; string_of_int i.m; string_of_int i.seed;
      meth_name meth; status; h; w; calls; queries; shrink; iters; bound; within; equals;
      hrec; complete; in_w; ot; bt; wall; peak; dg;
    ]

let run_job cfg i meth =
  let h = build i in
  let nh = List.length h in
  let u = Synth.universe i.n in
  let pred = Synth.achieves h in
  let t0 = Unix.gettimeofday () in
  match meth with
  | Alg1 | Padded | Padded_shrink ->
      let oracle =
        match meth with
        | Alg1 -> Synth.hypergraph_oracle h
        | _ ->
            Synth.padded_oracle ~extra:cfg.pad_extra
              (Random.State.make [| 7; i.n; i.m; i.seed |])
              ~u h
      in
      let w, h', st = Loop.weakest ~shrink:(meth = Padded_shrink) ~u oracle in
      let wall = Unix.gettimeofday () -. t0 in
      let nw = List.length w in
      let bound, within, equals =
        match meth with
        | Alg1 -> (nh + nw, st.distinct <= nh + nw, b2s (st.distinct = nh + nw))
        | Padded -> (nh + nw, true, b2s (st.distinct = nh + nw))
        | _ -> (nw + (nh * (1 + i.n)), st.distinct <= nw + (nh * (1 + i.n)), "")
      in
      row i meth ~status:"ok" ~h:(string_of_int nh) ~w:(string_of_int nw)
        ~calls:(string_of_int st.distinct) ~queries:(string_of_int st.queries)
        ~shrink:(string_of_int st.shrink_calls) ~iters:(string_of_int st.iterations)
        ~bound:(string_of_int bound)
        ~within:(if meth = Padded then "" else b2s within)
        ~equals ~hrec:(b2s (Clutter.equal_family h' h)) ~ot:(f6 st.oracle_time)
        ~bt:(f6 st.blocker_time) ~wall:(f6 wall) ~peak:(Printf.sprintf "%.1f" (peak_heap_mb ()))
        ~dg:(digest w) ()
  | B1 ->
      let w = Loop.brute_force ~u pred in
      let wall = Unix.gettimeofday () -. t0 in
      row i meth ~status:"ok" ~h:(string_of_int nh) ~w:(string_of_int (List.length w))
        ~calls:(string_of_int (1 lsl i.n)) ~complete:"1" ~wall:(f6 wall)
        ~peak:(Printf.sprintf "%.1f" (peak_heap_mb ())) ~dg:(digest w) ()
  | B2 ->
      let r = Loop.levelwise ~budget:cfg.b2_budget ~u pred in
      let wall = Unix.gettimeofday () -. t0 in
      row i meth ~status:"ok" ~h:(string_of_int nh)
        ~w:(if r.complete then string_of_int (List.length r.found) else "")
        ~calls:(string_of_int r.calls) ~complete:(b2s r.complete) ~wall:(f6 wall)
        ~peak:(Printf.sprintf "%.1f" (peak_heap_mb ()))
        ~dg:(if r.complete then digest r.found else "")
        ()
  | B3 ->
      let ans, calls = Loop.greedy_rgl ~u pred in
      let wall = Unix.gettimeofday () -. t0 in
      let in_w =
        match ans with
        | None -> false
        | Some t -> pred t && Aset.for_all (fun a -> not (pred (Aset.remove a t))) t
      in
      row i meth ~status:"ok" ~h:(string_of_int nh) ~calls:(string_of_int calls)
        ~in_w:(b2s in_w) ~wall:(f6 wall) ~peak:(Printf.sprintf "%.1f" (peak_heap_mb ())) ()

(* ---- forked execution with timeout and heap cap ----------------------------- *)

type running = {
  pid : int;
  fd : Unix.file_descr;
  start : float;
  buf : Buffer.t;
  on_done : status:string -> string -> unit;
      (* status ok/timeout/memout/crash, child output *)
}

let write_all fd s =
  let b = Bytes.of_string s in
  let rec go off =
    if off < Bytes.length b then go (off + Unix.write fd b off (Bytes.length b - off))
  in
  go 0

(* Fork a child that runs [f] and writes its result (one line) to a pipe. The heap
   cap is checked at the end of every major GC cycle. *)
let spawn ~mem_cap_mb f on_done =
  flush_all ();
  let r, w = Unix.pipe ~cloexec:true () in
  match Unix.fork () with
  | 0 ->
      Unix.close r;
      let cap_words = mem_cap_mb * 1048576 / (Sys.word_size / 8) in
      ignore
        (Gc.create_alarm (fun () ->
             if (Gc.quick_stat ()).heap_words > cap_words then (
               write_all w "MEMOUT\n";
               Unix._exit 3)));
      (try write_all w (f () ^ "\n")
       with e -> write_all w ("CRASH " ^ Printexc.to_string e ^ "\n"));
      Unix._exit 0
  | pid ->
      Unix.close w;
      { pid; fd = r; start = Unix.gettimeofday (); buf = Buffer.create 256; on_done }

let finish c =
  Unix.close c.fd;
  let _, st = Unix.waitpid [] c.pid in
  let out = String.trim (Buffer.contents c.buf) in
  let status =
    if out = "MEMOUT" then "memout"
    else if String.length out >= 5 && String.sub out 0 5 = "CRASH" then "crash"
    else if out = "" then
      match st with
      | Unix.WEXITED k -> Printf.sprintf "crash(exit %d)" k
      | Unix.WSIGNALED k -> Printf.sprintf "crash(signal %d)" k
      | Unix.WSTOPPED _ -> "crash"
    else "ok"
  in
  c.on_done ~status out

(* Poll the running children: read output, reap finished ones, kill overdue ones.
   Returns the children still running. *)
let poll ~timeout running =
  let fds = List.map (fun c -> c.fd) running in
  let ready, _, _ =
    try Unix.select fds [] [] 0.2 with Unix.Unix_error (Unix.EINTR, _, _) -> ([], [], [])
  in
  let chunk = Bytes.create 65536 in
  let now = Unix.gettimeofday () in
  List.filter
    (fun c ->
      if List.mem c.fd ready then begin
        let k = Unix.read c.fd chunk 0 (Bytes.length chunk) in
        if k = 0 then (
          finish c;
          false)
        else (
          Buffer.add_subbytes c.buf chunk 0 k;
          true)
      end
      else if now -. c.start > timeout then begin
        (try Unix.kill c.pid Sys.sigkill with Unix.Unix_error _ -> ());
        ignore (Unix.waitpid [] c.pid);
        Unix.close c.fd;
        c.on_done ~status:"timeout" "";
        false
      end
      else true)
    running

let run_sequential ~timeout ~mem_cap_mb f on_done =
  let rec wait l = if l <> [] then wait (poll ~timeout l) in
  wait [ spawn ~mem_cap_mb f on_done ]

(* ---- counts phase ------------------------------------------------------------- *)

let series_key i meth =
  (* random families: one series per (family, method); others likewise *)
  (i.family, meth)

let counts_phase cfg =
  let path = Filename.concat cfg.out "scale_counts.csv" in
  let oc = open_out path in
  output_string oc (counts_header ^ "\n");
  flush oc;
  let insts = instances cfg in
  (* pending jobs ordered by n so a series advances level by level *)
  let pending =
    ref
      (List.stable_sort
         (fun (a, _) (b, _) -> Int.compare a.n b.n)
         (List.concat_map (fun i -> List.map (fun m -> (i, m)) (methods cfg i)) insts))
  in
  let dead = Hashtbl.create 16 in
  (* unfinished jobs per series, by n *)
  let unfinished = Hashtbl.create 64 in
  List.iter
    (fun (i, m) ->
      let k = series_key i m in
      Hashtbl.replace unfinished k (i.n :: Option.value ~default:[] (Hashtbl.find_opt unfinished k)))
    !pending;
  let remove_one n l =
    let rec go = function [] -> [] | x :: r -> if x = n then r else x :: go r in
    go l
  in
  let total = List.length !pending and done_ = ref 0 and skipped = ref 0 in
  let t_start = Unix.gettimeofday () in
  let eligible (i, m) =
    let k = series_key i m in
    List.for_all (fun n' -> n' >= i.n) (Option.value ~default:[] (Hashtbl.find_opt unfinished k))
  in
  let running = ref [] in
  let launch (i, m) =
    let k = series_key i m in
    let on_done ~status out =
      incr done_;
      Hashtbl.replace unfinished k (remove_one i.n (Hashtbl.find unfinished k));
      let line =
        if status = "ok" then out
        else (
          Hashtbl.replace dead k i.n;
          row i m ~status ~h:"" ~wall:(if status = "timeout" then f6 cfg.timeout else "") ())
      in
      output_string oc (line ^ "\n");
      flush oc;
      if status <> "ok" || !done_ mod 200 = 0 then
        Printf.printf "[%7.0fs] %d/%d done; %s %s n=%d seed=%d: %s\n%!"
          (Unix.gettimeofday () -. t_start) !done_ total i.family (meth_name m) i.n i.seed
          status
    in
    running := spawn ~mem_cap_mb:cfg.mem_cap_mb (fun () -> run_job cfg i m) on_done :: !running
  in
  while !pending <> [] || !running <> [] do
    (* drop jobs of dead series beyond the level that died *)
    pending :=
      List.filter
        (fun (i, m) ->
          let k = series_key i m in
          match Hashtbl.find_opt dead k with
          | Some n0 when i.n > n0 ->
              incr skipped;
              Hashtbl.replace unfinished k (remove_one i.n (Hashtbl.find unfinished k));
              false
          | _ -> true)
        !pending;
    let rec fill acc = function
      | [] -> List.rev acc
      | j :: rest when List.length !running < cfg.jobs && eligible j ->
          launch j;
          fill acc rest
      | j :: rest -> fill (j :: acc) rest
    in
    pending := fill [] !pending;
    if !running <> [] then running := poll ~timeout:cfg.timeout !running
  done;
  close_out oc;
  Printf.printf "counts: %d jobs run, %d skipped after a timeout in their series, %.0f s\n%!"
    !done_ !skipped
    (Unix.gettimeofday () -. t_start)

(* ---- gadget phase ------------------------------------------------------------- *)

let gadget_instances cfg =
  let fixed =
    [
      ("fixed-1", 4, [ [ 0; 1 ]; [ 1; 2 ]; [ 3 ] ]);
      ("fixed-2", 4, [ [ 0 ]; [ 1; 2; 3 ] ]);
      ("fixed-3", 4, [ [ 0; 1 ]; [ 2; 3 ] ]);
      ("fixed-4", 5, [ [ 0; 1; 2 ]; [ 2; 3 ]; [ 4; 0 ] ]);
      ("fixed-5", 5, [ [ 3; 4 ]; [ 2; 3 ]; [ 0; 2; 4 ]; [ 0; 3 ] ]);
    ]
    |> List.map (fun (id, n, e) -> (id, n, 0, 0, Synth.of_indices e))
  in
  let ns = if cfg.quick then [ 4 ] else [ 4; 5; 6 ] in
  let rand =
    List.concat_map
      (fun n ->
        List.map
          (fun seed ->
            let m = min n 4 in
            let h =
              Synth.random (Synth.random_state ~family:"gadget" ~n ~m ~seed) ~n ~m
            in
            (Printf.sprintf "rand-n%d-s%d" n seed, n, m, seed, h))
          cfg.gadget_seeds)
      ns
  in
  (* one five-edge instance as a stress case (about 4 minutes) *)
  let stress =
    if cfg.quick then []
    else
      [ ("stress-n6-m6", 6, 6, 0,
         Synth.random (Synth.random_state ~family:"gadget" ~n:6 ~m:6 ~seed:0) ~n:6 ~m:6) ]
  in
  fixed @ rand @ stress

let edges_string h =
  String.concat " "
    (List.map
       (fun e -> String.concat "." (List.map (fun a -> string_of_int (Synth.index a)) (Aset.elements e)))
       h)

let gadget_phase cfg =
  let path = Filename.concat cfg.out "gadget_check.csv" in
  let oc = open_out path in
  output_string oc
    "id,n,m_raw,seed,H,W,edges,status,trusts,agree,loop_w_equal,loop_h_equal,gadget_distinct,time\n";
  let all_ok = ref true in
  List.iter
    (fun (id, n, m, seed, h) ->
      let pre =
        Printf.sprintf "%s,%d,%d,%d,%d,%d,%s" id n m seed (List.length h)
          (List.length (Clutter.blocker h)) (edges_string h)
      in
      run_sequential ~timeout:cfg.timeout ~mem_cap_mb:cfg.mem_cap_mb
        (fun () ->
          let c = Gadget.check ~n h in
          Printf.sprintf "%d,%d,%s,%s,%d,%.3f" c.trusts c.agree (b2s c.loop_w_equal)
            (b2s c.loop_h_equal) c.gadget_distinct c.time)
        (fun ~status out ->
          let line = if status = "ok" then pre ^ ",ok," ^ out else pre ^ "," ^ status ^ ",,,,,," in
          (match String.split_on_char ',' line with
          | l when status = "ok" ->
              let a = List.nth l 9 and t = List.nth l 8 in
              if a <> t || List.nth l 10 <> "1" || List.nth l 11 <> "1" then all_ok := false
          | _ -> all_ok := false);
          Printf.printf "gadget %-12s n=%d |H|=%d: %s\n%!" id n (List.length h)
            (if status = "ok" then out else status);
          output_string oc (line ^ "\n");
          flush oc))
    (gadget_instances cfg);
  close_out oc;
  Printf.printf "gadget: %s\n%!" (if !all_ok then "all instances agree" else "DISAGREEMENT or failure, see CSV")

(* ---- timing phase ------------------------------------------------------------- *)

(* Read scale_counts.csv as a list of association lists. *)
let read_csv path =
  let ic = open_in path in
  let header = String.split_on_char ',' (input_line ic) in
  let rows = ref [] in
  (try
     while true do
       let l = input_line ic in
       rows := List.combine header (String.split_on_char ',' l) :: !rows
     done
   with End_of_file -> ());
  close_in ic;
  List.rev !rows

let get r k = List.assoc k r

let median_iqr xs =
  let a = Array.of_list (List.sort compare xs) in
  let n = Array.length a in
  let q p =
    (* linear interpolation between order statistics *)
    let x = p *. float_of_int (n - 1) in
    let lo = int_of_float (floor x) and hi = int_of_float (ceil x) in
    a.(lo) +. ((x -. float_of_int lo) *. (a.(hi) -. a.(lo)))
  in
  (q 0.5, q 0.75 -. q 0.25)

(* Table groups: for each random family, n = 20 (m = n, 2n only) and the largest n at
   which every seed's alg1 run finished; for each deterministic family the largest n
   finished. scripts/scale_table.py uses the rows flagged here. *)
let table_groups counts =
  let alg1 = List.filter (fun r -> get r "method" = "alg1") counts in
  let fams = List.sort_uniq compare (List.map (fun r -> get r "family") alg1) in
  List.concat_map
    (fun f ->
      let rows = List.filter (fun r -> get r "family" = f) alg1 in
      let ns = List.sort_uniq compare (List.map (fun r -> int_of_string (get r "n")) rows) in
      let full =
        List.filter
          (fun n ->
            List.for_all
              (fun r -> int_of_string (get r "n") <> n || get r "status" = "ok")
              rows)
          ns
      in
      match List.rev full with
      | [] -> []
      | nmax :: _ ->
          let extra =
            if (f = "rand-m1" || f = "rand-m2") && nmax > 20 && List.mem 20 full then [ 20 ]
            else []
          in
          List.map (fun n -> (f, n)) (extra @ [ nmax ]))
    fams

let timing_header =
  "family,n,m,seed,table,reps,H,W,calls,wall_median,wall_iqr,oracle_median,blocker_median,\
   peak_heap_mb,walls"

let timing_phase cfg =
  let counts = read_csv (Filename.concat cfg.out "scale_counts.csv") in
  let groups = table_groups counts in
  let alg1_ok =
    List.filter (fun r -> get r "method" = "alg1" && get r "status" = "ok") counts
  in
  let selected =
    List.filter
      (fun r ->
        get r "seed" = "0"
        || List.mem (get r "family", int_of_string (get r "n")) groups)
      alg1_ok
  in
  let est =
    List.fold_left (fun acc r -> acc +. (5. *. float_of_string (get r "wall"))) 0. selected
  in
  Printf.printf "timing: %d runs selected, table groups %s; estimate up to %.0f s\n%!"
    (List.length selected)
    (String.concat " " (List.map (fun (f, n) -> Printf.sprintf "%s/%d" f n) groups))
    est;
  let oc = open_out (Filename.concat cfg.out "scale_timing.csv") in
  output_string oc (timing_header ^ "\n");
  List.iter
    (fun r ->
      let i =
        {
          family = get r "family";
          n = int_of_string (get r "n");
          m = int_of_string (get r "m");
          seed = int_of_string (get r "seed");
        }
      in
      let w0 = float_of_string (get r "wall") in
      let reps = if w0 < 60. then 5 else if w0 < 300. then 3 else 1 in
      let res = ref [] in
      for _ = 1 to reps do
        run_sequential ~timeout:cfg.timeout ~mem_cap_mb:cfg.mem_cap_mb
          (fun () -> run_job cfg i Alg1)
          (fun ~status out ->
            if status = "ok" then
              let l = List.combine (String.split_on_char ',' counts_header)
                  (String.split_on_char ',' out) in
              res :=
                ( float_of_string (get l "wall"),
                  float_of_string (get l "oracle_time"),
                  float_of_string (get l "blocker_time"),
                  get l "peak_heap_mb" )
                :: !res)
      done;
      let walls = List.map (fun (w, _, _, _) -> w) !res in
      let line =
        if walls = [] then
          Printf.sprintf "%s,%d,%d,%d,%s,0,%s,%s,%s,,,,,," i.family i.n i.m i.seed
            (b2s (List.mem (i.family, i.n) groups))
            (get r "H") (get r "W") (get r "calls")
        else
          let wm, wi = median_iqr walls in
          let om, _ = median_iqr (List.map (fun (_, o, _, _) -> o) !res) in
          let bm, _ = median_iqr (List.map (fun (_, _, b, _) -> b) !res) in
          let _, _, _, pk = List.hd !res in
          Printf.sprintf "%s,%d,%d,%d,%s,%d,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%s,%s" i.family i.n
            i.m i.seed
            (b2s (List.mem (i.family, i.n) groups))
            (List.length walls) (get r "H") (get r "W") (get r "calls") wm wi om bm pk
            (String.concat ";" (List.map (Printf.sprintf "%.6f") (List.rev walls)))
      in
      output_string oc (line ^ "\n");
      flush oc)
    selected;
  close_out oc

(* ---- manifest ----------------------------------------------------------------- *)

let cmd c =
  try
    let ic = Unix.open_process_in (c ^ " 2>/dev/null") in
    let s = In_channel.input_all ic in
    ignore (Unix.close_process_in ic);
    String.trim s
  with _ -> "?"

let sources_digest () =
  let files =
    List.concat_map
      (fun d ->
        try
          Sys.readdir d |> Array.to_list
          |> List.filter (fun f -> Filename.check_suffix f ".ml" || Filename.check_suffix f ".mli")
          |> List.sort compare
          |> List.map (Filename.concat d)
        with Sys_error _ -> [])
      [ "lib"; "bin" ]
  in
  ( List.length files,
    Digest.to_hex
      (Digest.string
         (String.concat ""
            (List.map (fun f -> f ^ Digest.to_hex (Digest.file f)) files))) )

let manifest cfg phases =
  let oc = open_out (Filename.concat cfg.out "manifest_scale.txt") in
  let p fmt = Printf.fprintf oc fmt in
  let nf, dg = sources_digest () in
  p "experiment: E3 (scale) and gadget validity, trust scale%s\n" (if cfg.quick then " --quick" else "");
  p "phases: %s\n" (String.concat " " phases);
  p "date: %s\n" (cmd "date -u +%Y-%m-%dT%H:%M:%SZ");
  p "ocaml: %s; ocamlopt %s; flambda: %s; dune %s\n" Sys.ocaml_version
    (cmd "ocamlfind ocamlopt -version") (cmd "ocamlfind ocamlopt -config-var flambda")
    (cmd "dune --version");
  p "build: dune build --profile release (scripts/run_scale.sh); no extra ocamlopt flags\n";
  p "machine: %s; %s cores (%s performance, %s efficiency); memory %s bytes\n"
    (cmd "sysctl -n machdep.cpu.brand_string") (cmd "sysctl -n hw.ncpu")
    (cmd "sysctl -n hw.perflevel0.physicalcpu") (cmd "sysctl -n hw.perflevel1.physicalcpu")
    (cmd "sysctl -n hw.memsize");
  p "os: %s %s\n" (cmd "sw_vers -productName") (cmd "sw_vers -productVersion");
  p "sources: %d files under lib/ and bin/, digest %s\n" nf dg;
  p "seeds: %s (random families); instance RNG = Synth.random_state ~family ~n ~m ~seed;\n"
    (String.concat " " (List.map string_of_int cfg.seeds));
  p "  padded witnesses: missed edge + %d atoms of U \\ (T + edge) drawn uniformly, RNG = Random.State.make [|7; n; m; seed|]\n"
    cfg.pad_extra;
  p "  gadget: fixed instances of scale.py plus Synth.random with m = min(n, 4) raw edges, n = 4, 5, 6, plus one stress instance n = m = 6, seeds %s\n"
    (String.concat " " (List.map string_of_int cfg.gadget_seeds));
  p "families: rand-m1/m2/m4 (m = n, 2n, 4n edges, sizes 1-3, minimalised), n = %s;\n"
    (String.concat " " (List.map string_of_int cfg.rand_ns));
  p "  pairs, dual (blocker of pairs), n = %s; thr (all n/2-subsets), thr-dual (all (n/2+1)-subsets), n = %s\n"
    (String.concat " " (List.map string_of_int cfg.pair_ns))
    (String.concat " " (List.map string_of_int cfg.thr_ns));
  p "methods: alg1 (minimal witnesses), padded, padded_shrink, b1 (n <= %d), b2 (budget %d), b3\n"
    cfg.b1_max cfg.b2_budget;
  p "counts phase: %d parallel workers (forked children); timeout %.0f s per run (SIGKILL by parent), heap cap %d MB (Gc alarm);\n"
    cfg.jobs cfg.timeout cfg.mem_cap_mb;
  p "  a series (family, method) stops at the first n with a timeout, memout or crash; that run is recorded\n";
  p "timing phase: sequential, one child at a time; alg1 for seed 0 of every finished (family, n, m) and every seed of the\n";
  p "  table groups; 5 repetitions if the counts-phase wall < 60 s, 3 if < 300 s, else 1; median and IQR (linear interpolation)\n";
  p "peak memory: Gc top_heap_words of the child (major heap peak), MB\n";
  close_out oc

(* ---- entry ---------------------------------------------------------------------- *)

let main args =
  let quick = List.mem "--quick" args in
  let rec opt k = function
    | a :: v :: _ when a = k -> Some v
    | _ :: r -> opt k r
    | [] -> None
  in
  let out = Option.value ~default:(if quick then "results/quick" else "results") (opt "--out" args) in
  let jobs = Option.fold ~none:10 ~some:int_of_string (opt "--jobs" args) in
  let cfg = (if quick then quick_config else full_config) out jobs in
  let cfg =
    match opt "--timeout" args with Some t -> { cfg with timeout = float_of_string t } | None -> cfg
  in
  let phases =
    match opt "--phase" args with
    | None | Some "all" -> [ "counts"; "gadget"; "timing" ]
    | Some p -> String.split_on_char ',' p
  in
  let rec mkdir d =
    if not (Sys.file_exists d) then (
      mkdir (Filename.dirname d);
      Sys.mkdir d 0o755)
  in
  mkdir cfg.out;
  manifest cfg phases;
  List.iter
    (function
      | "counts" -> counts_phase cfg
      | "gadget" -> gadget_phase cfg
      | "timing" -> timing_phase cfg
      | p -> failwith ("unknown phase " ^ p))
    phases
