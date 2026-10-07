(* CPSA 4 driver: templates, runs, verdicts, replay, and the oracle. See cpsa.mli. *)

module Sexp = struct
  type t = Atom of string | List of t list

  let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012'

  let parse_all s =
    let n = String.length s in
    let stack = ref [ [] ] in
    let push x =
      match !stack with top :: rest -> stack := (x :: top) :: rest | [] -> assert false
    in
    let i = ref 0 in
    while !i < n do
      let c = s.[!i] in
      if is_space c then incr i
      else if c = ';' then (
        while !i < n && s.[!i] <> '\n' do incr i done)
      else if c = '(' then (
        stack := [] :: !stack;
        incr i)
      else if c = ')' then (
        (match !stack with
        | top :: (_ :: _ as rest) ->
            stack := rest;
            push (List (List.rev top))
        | _ -> failwith (Printf.sprintf "Sexp.parse_all: unbalanced ')' at %d" !i));
        incr i)
      else if c = '"' then (
        let j = ref (!i + 1) in
        while !j < n && s.[!j] <> '"' do
          if s.[!j] = '\\' then incr j;
          incr j
        done;
        if !j >= n then failwith "Sexp.parse_all: unterminated string";
        push (Atom (String.sub s !i (!j - !i + 1)));
        i := !j + 1)
      else (
        let j = ref !i in
        while
          !j < n
          && (let d = s.[!j] in
              not (is_space d || d = '(' || d = ')' || d = '"' || d = ';'))
        do
          incr j
        done;
        push (Atom (String.sub s !i (!j - !i)));
        i := !j)
    done;
    match !stack with
    | [ top ] -> List.rev top
    | _ -> failwith "Sexp.parse_all: unbalanced '('"

  let rec to_string = function
    | Atom a -> a
    | List l -> "(" ^ String.concat " " (List.map to_string l) ^ ")"

  let field form key =
    match form with
    | List l ->
        List.filter (function List (Atom h :: _) -> h = key | _ -> false) l
    | Atom _ -> []
end

open Sexp

(* ---- strings ---- *)

let find_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i =
    if i + m > n then None else if String.sub s i m = sub then Some i else go (i + 1)
  in
  go 0

let count_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i k =
    if i + m > n then k
    else if String.sub s i m = sub then go (i + m) (k + 1)
    else go (i + 1) k
  in
  go 0 0

let contains s sub = find_sub s sub <> None
let trim = String.trim

(* ---- templates ---- *)

type template = {
  path : string;
  name : string;
  meta : (string * string) list;
  u : (string * string) list;
  proto : string;
  goal_text : string;
}

let placeholder = "@TRUST@"

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let is_word_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'

(* ";;\s*@(\w+)\s+(.*)$" *)
let header_line line =
  let n = String.length line in
  if n < 2 || String.sub line 0 2 <> ";;" then None
  else
    let i = ref 2 in
    while !i < n && Sexp.is_space line.[!i] do incr i done;
    if !i >= n || line.[!i] <> '@' then None
    else
      let k0 = !i + 1 in
      let j = ref k0 in
      while !j < n && is_word_char line.[!j] do incr j done;
      if !j = k0 || !j >= n || not (Sexp.is_space line.[!j]) then None
      else Some (String.sub line k0 (!j - k0), trim (String.sub line !j (n - !j)))

let starts_with ~prefix s =
  String.length s >= String.length prefix
  && String.sub s 0 (String.length prefix) = prefix

let load_template path =
  let text = read_file path in
  let lines = String.split_on_char '\n' text in
  let meta = ref [] and u = ref [] in
  List.iter
    (fun line ->
      match header_line line with
      | Some ("U", v) -> (
          match String.index_from_opt v 0 ' ' with
          | Some k ->
              u := (String.sub v 0 k, trim (String.sub v k (String.length v - k))) :: !u
          | None -> failwith (path ^ ": @U line without a fact: " ^ line))
      | Some (k, v) -> meta := (k, v) :: !meta
      | None -> ())
    lines;
  let meta = List.rev !meta and u = List.rev !u in
  let name =
    match List.assoc_opt "name" meta with
    | Some n -> n
    | None -> failwith (path ^ ": no ;; @name line")
  in
  let body =
    String.concat "\n" (List.filter (fun l -> not (starts_with ~prefix:";; @" l)) lines)
  in
  let i =
    match find_sub body "(defgoal" with
    | Some i -> i
    | None -> failwith (path ^ ": no (defgoal")
  in
  let proto = trim (String.sub body 0 i) ^ "\n" in
  let goal_text = trim (String.sub body i (String.length body - i)) ^ "\n" in
  if count_sub goal_text placeholder <> 1 || contains proto placeholder then
    failwith (path ^ ": need exactly one " ^ placeholder ^ ", in the defgoal");
  let ids = List.map fst u in
  if List.length (List.sort_uniq compare ids) <> List.length ids then
    failwith (path ^ ": duplicate @U atom id");
  { path; name; meta; u; proto; goal_text }

let templates_in dir =
  Sys.readdir dir |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".scm")
  |> List.sort compare
  |> List.map (Filename.concat dir)

let universe t = Aset.of_list (List.map fst t.u)
let fact t a = List.assoc a t.u

let goal_source t trust =
  let facts = List.map (fact t) (Aset.elements trust) in
  let i = Option.get (find_sub t.goal_text placeholder) in
  let k = String.length placeholder in
  let goal =
    String.sub t.goal_text 0 i
    ^ String.concat "\n           " facts
    ^ String.sub t.goal_text (i + k) (String.length t.goal_text - i - k)
  in
  Printf.sprintf "(herald \"%s trust\")\n%s\n%s" t.name t.proto goal

(* ---- running CPSA ---- *)

exception Cpsa_error of string

let executable p =
  try
    Unix.access p [ Unix.X_OK ];
    not (Sys.is_directory p)
  with Unix.Unix_error _ | Sys_error _ -> false

let binary () =
  match Sys.getenv_opt "CPSA4" with
  | Some p when p <> "" -> if executable p then Some p else None
  | _ -> (
      let path = Option.value (Sys.getenv_opt "PATH") ~default:"" in
      let on_path =
        String.split_on_char ':' path
        |> List.filter (( <> ) "")
        |> List.map (fun d -> Filename.concat d "cpsa4")
        |> List.find_opt executable
      in
      match on_path with
      | Some p -> Some p
      | None -> (
          match Sys.getenv_opt "HOME" with
          | Some h ->
              let p = Filename.concat h ".local/bin/cpsa4" in
              if executable p then Some p else None
          | None -> None))

let binary_exn () =
  match binary () with
  | Some p -> p
  | None -> raise (Cpsa_error "cpsa4 not found (set CPSA4, or put cpsa4 on PATH)")

type run = {
  stdout : string;
  stderr : string;
  status : Unix.process_status option;
  time : float;
}

(* Run [prog args] with stdin from /dev/null, collecting stdout and stderr through
   pipes; kill the process after [timeout] seconds. *)
let run_process ~timeout prog args =
  let out_r, out_w = Unix.pipe ~cloexec:true () in
  let err_r, err_w = Unix.pipe ~cloexec:true () in
  let null = Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
  let t0 = Unix.gettimeofday () in
  let pid =
    Fun.protect
      ~finally:(fun () -> List.iter Unix.close [ out_w; err_w; null ])
      (fun () -> Unix.create_process prog (Array.of_list (prog :: args)) null out_w err_w)
  in
  let bout = Buffer.create 65536 and berr = Buffer.create 256 in
  let chunk = Bytes.create 65536 in
  let open_fds = ref [ out_r; err_r ] in
  let deadline = t0 +. timeout in
  let timed_out = ref false in
  while !open_fds <> [] && not !timed_out do
    let left = deadline -. Unix.gettimeofday () in
    if left <= 0. then timed_out := true
    else
      match Unix.select !open_fds [] [] left with
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> ()
      | ready, _, _ ->
          List.iter
            (fun fd ->
              let k = Unix.read fd chunk 0 (Bytes.length chunk) in
              if k = 0 then (
                Unix.close fd;
                open_fds := List.filter (fun x -> x != fd) !open_fds)
              else Buffer.add_subbytes (if fd == out_r then bout else berr) chunk 0 k)
            ready
  done;
  if !timed_out then (
    (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
    List.iter Unix.close !open_fds);
  let rec wait () =
    match Unix.waitpid [] pid with
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
    | _, st -> st
  in
  let st = wait () in
  let time = Unix.gettimeofday () -. t0 in
  {
    stdout = Buffer.contents bout;
    stderr = Buffer.contents berr;
    status = (if !timed_out then None else Some st);
    time;
  }

let run_cpsa ?(timeout = 600.) src =
  let bin = binary_exn () in
  let path = Filename.temp_file "trust_cpsa" ".scm" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc src;
      close_out oc;
      run_process ~timeout bin [ path ])

let version () =
  let r = run_process ~timeout:30. (binary_exn ()) [ "--version" ] in
  let s = trim (r.stdout ^ "\n" ^ r.stderr) in
  match String.split_on_char '\n' s with l :: _ -> trim l | [] -> ""

(* ---- reading goal runs ---- *)

type failing = { shape : Sexp.t; binding : Sexp.t }

type goal_result = {
  incomplete : string option;
  skeletons : int;
  shapes : int;
  failing : failing list;
}

let is_head h = function List (Atom x :: _) -> x = h | _ -> false
let skeletons_of forms = List.filter (is_head "defskeleton") forms

let comments forms =
  List.filter_map
    (function List [ Atom "comment"; Atom s ] -> Some s | _ -> None)
    forms

let incomplete_reason r forms =
  let low = String.lowercase_ascii r.stdout in
  match r.status with
  | None -> Some "timeout"
  | Some (Unix.WEXITED c) when c <> 0 -> Some (Printf.sprintf "exit status %d" c)
  | Some (Unix.WSIGNALED s | Unix.WSTOPPED s) -> Some (Printf.sprintf "signal %d" s)
  | Some _ ->
      if trim r.stderr <> "" then Some ("stderr: " ^ trim r.stderr)
      else if not (List.mem "\"Nothing left to do\"" (comments forms)) then
        Some "no \"Nothing left to do\""
      else if List.exists (fun s -> Sexp.field s "aborted" <> []) (skeletons_of forms) then
        Some "aborted skeleton"
      else
        List.find_map
          (fun w -> if contains low w then Some w else None)
          [ "step limit exceeded"; "strand bound exceeded"; "aborting" ]

let read_goal_output r =
  match Sexp.parse_all r.stdout with
  | exception Failure msg ->
      { incomplete = Some ("unparsable output: " ^ msg); skeletons = 0; shapes = 0; failing = [] }
  | forms ->
      let sks = skeletons_of forms in
      let shapes = List.filter (fun s -> Sexp.field s "shape" <> []) sks in
      let failing =
        List.concat_map
          (fun s ->
            List.filter_map
              (function
                | List (_ :: (List (Atom "no" :: _) as b) :: _) -> Some { shape = s; binding = b }
                | _ -> None)
              (Sexp.field s "satisfies"))
          shapes
      in
      {
        incomplete = incomplete_reason r forms;
        skeletons = List.length sks;
        shapes = List.length shapes;
        failing;
      }

let achieves_of g = g.failing = []

(* ---- replay ---- *)

let rec subst env = function
  | Atom a as x -> ( match List.assoc_opt a env with Some v -> v | None -> x)
  | List l -> List (List.map (subst env) l)

let env_of_binding = function
  | List (_ :: items) ->
      (* later bindings of the same name win, as in a Python dict *)
      List.rev
        (List.filter_map (function List [ Atom v; t ] -> Some (v, t) | _ -> None) items)
  | _ -> []

let keep =
  [ "vars"; "defstrand"; "deflistener"; "defstrandmax"; "precedes"; "leadsto"; "non-orig";
    "pen-non-orig"; "uniq-orig"; "uniq-gen"; "absent"; "conf"; "auth"; "facts"; "priority" ]

let replay_source t f atoms =
  let env = env_of_binding f.binding in
  (* extra: slot -> terms, slots in order of first use *)
  let extra = ref [] in
  List.iter
    (fun a ->
      match Sexp.parse_all (fact t a) with
      | [ List [ Atom kind; term ] ] ->
          let slot =
            match kind with
            | "non" -> "non-orig"
            | "uniq" -> "uniq-orig"
            | k -> failwith ("Cpsa.replay_source: fact kind " ^ k ^ " in atom " ^ a)
          in
          let term = subst env term in
          extra :=
            if List.mem_assoc slot !extra then
              List.map
                (fun (s, ts) -> if s = slot then (s, ts @ [ term ]) else (s, ts))
                !extra
            else !extra @ [ (slot, [ term ]) ]
      | _ -> failwith ("Cpsa.replay_source: cannot read fact of atom " ^ a))
    atoms;
  let name, fields =
    match f.shape with
    | List (_ :: name :: fields) -> (name, fields)
    | _ -> failwith "Cpsa.replay_source: malformed shape"
  in
  let kept =
    List.filter_map
      (function
        | List (Atom h :: args) as x when List.mem h keep -> (
            match List.assoc_opt h !extra with
            | Some ts ->
                extra := List.remove_assoc h !extra;
                Some (List ((Atom h :: args) @ List.filter (fun t -> not (List.mem t args)) ts))
            | None -> Some x)
        | _ -> None)
      fields
  in
  let added = List.map (fun (s, ts) -> List (Atom s :: ts)) !extra in
  let sk = List ((Atom "defskeleton" :: name :: kept) @ added) in
  "(herald \"stops check\")\n" ^ t.proto ^ "\n" ^ Sexp.to_string sk ^ "\n"

type replay_verdict = Realized | Unrealized | Rejected of string

let read_replay_output r =
  match r.status with
  | None -> raise (Cpsa_error "replay run timed out")
  | Some _ ->
      if trim r.stderr <> "" then
        let lines = String.split_on_char '\n' (trim r.stderr) in
        Rejected ("ill-formed: " ^ List.nth lines (List.length lines - 1))
      else
        let forms =
          try Sexp.parse_all r.stdout
          with Failure m -> raise (Cpsa_error ("replay output unparsable: " ^ m))
        in
        match skeletons_of forms with
        | [] -> Unrealized
        | first :: _ ->
            if Sexp.field first "preskeleton" <> [] then Rejected "preskeleton"
            else if Sexp.field first "dead" <> [] then Rejected "dead"
            else if Sexp.field first "realized" <> [] then Realized
            else Unrealized

let survives = function Realized -> true | Unrealized | Rejected _ -> false

(* ---- the oracle ---- *)

type stats = {
  mutable goal_runs : int;
  mutable replay_runs : int;
  mutable goal_time : float;
  mutable replay_time : float;
  mutable rejected : int;
  mutable ill_formed : int;
  mutable log : string list;
}

let new_stats () =
  {
    goal_runs = 0;
    replay_runs = 0;
    goal_time = 0.;
    replay_time = 0.;
    rejected = 0;
    ill_formed = 0;
    log = [];
  }

let cpsa_time s = s.goal_time +. s.replay_time

let goal_run ?timeout ?(stats = new_stats ()) t trust =
  let r = run_cpsa ?timeout (goal_source t trust) in
  stats.goal_runs <- stats.goal_runs + 1;
  stats.goal_time <- stats.goal_time +. r.time;
  let g = read_goal_output r in
  match g.incomplete with
  | Some why ->
      raise
        (Cpsa_error
           (Format.asprintf "%s: goal run at T = %a is not a complete search (%s)" t.name
              Aset.pp trust why))
  | None -> g

let verdict ?timeout ?stats t trust = achieves_of (goal_run ?timeout ?stats t trust)

let label_of shape =
  match Sexp.field shape "label" with
  | List [ _; Atom l ] :: _ -> l
  | _ -> "?"

let stops ?timeout ?(stats = new_stats ()) t trust f =
  let rest = Aset.diff (universe t) trust in
  let m = ref [] and why = ref [] in
  Aset.iter
    (fun a ->
      let r = run_cpsa ?timeout (replay_source t f (List.rev (a :: !m))) in
      stats.replay_runs <- stats.replay_runs + 1;
      stats.replay_time <- stats.replay_time +. r.time;
      let v = read_replay_output r in
      (match v with
      | Rejected s when starts_with ~prefix:"ill-formed" s -> stats.ill_formed <- stats.ill_formed + 1
      | Rejected _ -> stats.rejected <- stats.rejected + 1
      | _ -> ());
      let reason =
        match v with Realized -> "realized" | Unrealized -> "unrealized" | Rejected s -> s
      in
      why := (a ^ ": " ^ reason) :: !why;
      if survives v then m := a :: !m)
    rest;
  let clause = Aset.diff rest (Aset.of_list !m) in
  ( clause,
    Format.asprintf "shape %s: stops = %a  [%s]" (label_of f.shape) Aset.pp clause
      (String.concat "; " (List.rev !why)) )

let oracle ?timeout ?(stats = new_stats ()) t trust =
  let g = goal_run ?timeout ~stats t trust in
  if achieves_of g then (
    stats.log <-
      Format.asprintf "O(%a) = achieves [%d shape(s)]" Aset.pp trust g.shapes :: stats.log;
    Loop.Achieves)
  else
    let cands =
      List.map
        (fun f ->
          let c, line = stops ?timeout ~stats t trust f in
          stats.log <- Format.asprintf "O(%a) fails: %s" Aset.pp trust line :: stats.log;
          (c, line))
        g.failing
    in
    let best =
      List.fold_left
        (fun acc (c, l) ->
          match acc with
          | Some (c0, _) when Aset.compare_size_lex c0 c <= 0 -> acc
          | _ -> Some (c, l))
        None cands
    in
    let c, l = Option.get best in
    Loop.Fails
      { stops = c; descr = Printf.sprintf "%s (of %d failing shape(s))" l (List.length cands) }
