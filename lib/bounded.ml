type chan = string * string

type tmpl = T of Term.t | V of string | P of tmpl * tmpl | E of tmpl * tmpl | S of tmpl * tmpl

type dir = Send | Recv
type step = { dir : dir; chan : chan option; msg : tmpl }
type strand = { label : string; steps : step list }
type scenario = { sname : string; fixed : (int * string * Term.t) list }

type world = {
  k0 : Term.t list;
  auth : chan list;
  conf : chan list;
  scenarios : scenario list;
}

type view = { pos : int array; value : int -> string -> Term.t option; flags : int }
type event = { edir : dir; strand : int; step : int; echan : chan option; msg : Term.t }
type goal = { update : view -> event -> int; violated : view -> bool }

type model = {
  strands : strand array;
  values : Term.t list;
  world : Aset.t -> world;
  goal : goal;
  test : int list;
  hijack : bool;
}

type run = { scenario : string; events : event list }
type mode = As_found | Pruned | Least
type outcome = Achieves | Attack of { run : run; stops : Aset.t }
type result = { outcome : outcome; states : int; attack_states : int; nonprincipal : int }

exception Timeout

(* ---- derivability: analysis closure, then synthesis ------------------------------ *)

let rec synth an m =
  Term.Set.mem m an
  ||
  match m with
  | Term.Name _ -> false
  | Term.Pair (a, b) | Term.Enc (a, b) | Term.Sig (a, b) -> synth an a && synth an b

(* Close [an] (already closed) under projection, opening signatures, and decryption with
   a synthesisable inverse key, after adding [ts]. *)
let analz_add an ts =
  let an = ref an in
  let rec add t =
    if not (Term.Set.mem t !an) then begin
      an := Term.Set.add t !an;
      match t with
      | Term.Pair (a, b) ->
          add a;
          add b
      | Term.Sig (_, m) -> add m
      | Term.Enc _ | Term.Name _ -> ()
    end
  in
  List.iter add ts;
  let changed = ref true in
  while !changed do
    changed := false;
    Term.Set.iter
      (function
        | Term.Enc (k, m) when (not (Term.Set.mem m !an)) && synth !an (Term.inverse k) ->
            add m;
            changed := true
        | _ -> ())
      !an
  done;
  !an

let derivable known target = synth (analz_add Term.Set.empty known) target

(* ---- compiled model --------------------------------------------------------------- *)

type ct = CT of Term.t | CV of int | CP of ct * ct | CE of ct * ct | CS of ct * ct

type cstep = { cdir : dir; cchan : chan option; cmsg : ct; cvars : int list }

type compiled = {
  m : model;
  mutable atoms : Term.t array;
  atom_index : (Term.t, int) Hashtbl.t;
  value_idx : int array;  (* atom indices of model.values, in order *)
  steps : cstep array array;
  slot_of : (string, int) Hashtbl.t array;  (* per strand: variable -> slot *)
  nslots : int;
  strand_slots : int array array;  (* per strand: its slots, in allocation order *)
  group : int array;  (* symmetry group of the strand, -1 if none *)
  groups : int list list;  (* symmetry groups: non-test strands with identical steps *)
}

(* Atom table: the values, then scenario values interned on demand. *)
let atom_id c t =
  match Hashtbl.find_opt c.atom_index t with
  | Some i -> i
  | None ->
      let i = Array.length c.atoms in
      Hashtbl.add c.atom_index t i;
      c.atoms <- Array.append c.atoms [| t |];
      i

let make (m : model) =
  let nslots = ref 0 in
  let slot_of = Array.map (fun _ -> Hashtbl.create 4) m.strands in
  let steps =
    Array.mapi
      (fun i (s : strand) ->
        let slot v =
          match Hashtbl.find_opt slot_of.(i) v with
          | Some k -> k
          | None ->
              let k = !nslots in
              incr nslots;
              Hashtbl.add slot_of.(i) v k;
              k
        in
        let rec comp = function
          | T t -> CT t
          | V v -> CV (slot v)
          | P (a, b) -> CP (comp a, comp b)
          | E (a, b) -> CE (comp a, comp b)
          | S (a, b) -> CS (comp a, comp b)
        in
        let rec vars acc = function
          | T _ -> acc
          | V v -> if List.mem v acc then acc else v :: acc
          | P (a, b) | E (a, b) | S (a, b) -> vars (vars acc a) b
        in
        Array.of_list
          (List.map
             (fun (st : step) ->
               let cmsg = comp st.msg in
               let vs = List.sort compare (vars [] st.msg) in
               { cdir = st.dir; cchan = st.chan; cmsg; cvars = List.map slot vs })
             s.steps))
      m.strands
  in
  let strand_slots =
    Array.map
      (fun tbl -> Array.of_list (List.sort compare (Hashtbl.fold (fun _ s acc -> s :: acc) tbl [])))
      slot_of
  in
  let n = Array.length m.strands in
  let group = Array.make n (-1) in
  let groups = ref [] in
  for i = 0 to n - 1 do
    if group.(i) < 0 && not (List.mem i m.test) then begin
      let members =
        List.filter
          (fun j ->
            j >= i && group.(j) < 0 && (not (List.mem j m.test))
            && m.strands.(j).steps = m.strands.(i).steps)
          (List.init n Fun.id)
      in
      if List.length members >= 2 then begin
        let g = List.length !groups in
        List.iter (fun j -> group.(j) <- g) members;
        groups := members :: !groups
      end
    end
  done;
  let c =
    {
      m;
      atoms = [||];
      atom_index = Hashtbl.create 16;
      value_idx = [||];
      steps;
      slot_of;
      nslots = !nslots;
      strand_slots;
      group;
      groups = List.rev !groups;
    }
  in
  let value_idx = Array.of_list (List.map (atom_id c) m.values) in
  if Array.length c.atoms > 254 then invalid_arg "Bounded: more than 254 atoms";
  { c with value_idx }

let rec inst atoms bind = function
  | CT t -> t
  | CV s ->
      let i = bind.(s) in
      if i < 0 then invalid_arg "Bounded: unbound variable" else atoms.(i)
  | CP (a, b) -> Term.Pair (inst atoms bind a, inst atoms bind b)
  | CE (a, b) -> Term.Enc (inst atoms bind a, inst atoms bind b)
  | CS (a, b) -> Term.Sig (inst atoms bind a, inst atoms bind b)

(* match a template against a ground term, extending [bind] in place *)
let rec matcht c bind ct t =
  match (ct, t) with
  | CT g, _ -> Term.equal g t
  | CV s, _ -> (
      if bind.(s) >= 0 then Term.equal c.atoms.(bind.(s)) t
      else
        match Hashtbl.find_opt c.atom_index t with
        | Some i ->
            bind.(s) <- i;
            true
        | None -> false)
  | CP (a, b), Term.Pair (x, y) | CE (a, b), Term.Enc (x, y) | CS (a, b), Term.Sig (x, y) ->
      matcht c bind a x && matcht c bind b y
  | _ -> false

let view_of c pos bind flags =
  let value i v =
    match Hashtbl.find_opt c.slot_of.(i) v with
    | None -> None
    | Some s -> if bind.(s) < 0 then None else Some c.atoms.(bind.(s))
  in
  { pos; value; flags }

(* ---- worlds ------------------------------------------------------------------------ *)

type cworld = {
  w : world;
  an0 : Term.Set.t;
  k0set : Term.Set.t;
  is_auth : chan option -> bool;
  is_conf : chan option -> bool;
}

let cworld (w : world) =
  let mem l = function None -> false | Some c -> List.mem c l in
  {
    w;
    an0 = analz_add Term.Set.empty w.k0;
    k0set = Term.Set.of_list w.k0;
    is_auth = mem w.auth;
    is_conf = mem w.conf;
  }

let can_receive hijack cw an sent ch m =
  List.exists (fun (c', m') -> c' = ch && Term.equal m' m) sent
  || (not (cw.is_auth ch))
     && (synth an m || (hijack && List.exists (fun (_, m') -> Term.equal m' m) sent))

let find_scenario cw name = List.find_opt (fun s -> s.sname = name) cw.w.scenarios

let fix_scenario c (sc : scenario) bind =
  List.iter
    (fun (i, v, t) ->
      match Hashtbl.find_opt c.slot_of.(i) v with
      | Some s -> bind.(s) <- atom_id c t
      | None -> invalid_arg ("Bounded: scenario fixes unknown variable " ^ v))
    sc.fixed

(* ---- replay ------------------------------------------------------------------------ *)

(* Replay [run] in world [cw]; Some (pos, bind, flags) at the end, or None. *)
let replay_c cm cw (r : run) =
  match find_scenario cw r.scenario with
  | None -> None
  | Some sc -> (
      let c0 = cm in
      let bind = Array.make c0.nslots (-1) in
      fix_scenario cm sc bind;
      let c = cm in
      let pos = Array.make (Array.length c.steps) 0 in
      let an = ref cw.an0 and sent = ref [] and flags = ref 0 in
      let ok = ref true in
      (try
         List.iter
           (fun (e : event) ->
             let i = e.strand in
             if pos.(i) <> e.step || e.step >= Array.length c.steps.(i) then raise Exit;
             let st = c.steps.(i).(e.step) in
             if st.cdir <> e.edir || st.cchan <> e.echan then raise Exit;
             (match st.cdir with
             | Send ->
                 if not (Term.equal (inst c.atoms bind st.cmsg) e.msg) then raise Exit;
                 if not (cw.is_conf st.cchan) then an := analz_add !an [ e.msg ];
                 sent := (st.cchan, e.msg) :: !sent
             | Recv ->
                 if not (matcht c bind st.cmsg e.msg) then raise Exit;
                 if not (can_receive c.m.hijack cw !an !sent st.cchan e.msg) then raise Exit);
             pos.(i) <- pos.(i) + 1;
             flags := c.m.goal.update (view_of c pos bind !flags) e)
           r.events
       with Exit -> ok := false);
      if !ok then Some (pos, bind, !flags) else None)

let replays m t r =
  let cm = make m in
  replay_c cm (cworld (m.world t)) r <> None

let is_attack_c cm cw r =
  match replay_c cm cw r with
  | None -> false
  | Some (pos, bind, flags) -> cm.m.goal.violated (view_of cm pos bind flags)

let is_attack m t r =
  let cm = make m in
  is_attack_c cm (cworld (m.world t)) r

let stops_c cm ~u t r =
  Aset.filter
    (fun a -> replay_c cm (cworld (cm.m.world (Aset.add a t))) r = None)
    (Aset.diff u t)

let stops m ~u t r = stops_c (make m) ~u t r

let prune_c cm ~u t (r : run) =
  let cw = cworld (cm.m.world t) in
  let test = cm.m.test in
  let cur_stops = ref (stops_c cm ~u t r) in
  let r = ref r in
  let changed = ref true in
  while !changed do
    changed := false;
    let sids =
      List.sort_uniq compare
        (List.filter_map
           (fun (e : event) -> if List.mem e.strand test then None else Some e.strand)
           !r.events)
    in
    List.iter
      (fun sid ->
        let evs = Array.of_list !r.events in
        let last = ref (-1) in
        Array.iteri (fun i (e : event) -> if e.strand = sid then last := i) evs;
        if !last >= 0 then begin
          let cand =
            { !r with events = List.filteri (fun i _ -> i <> !last) !r.events }
          in
          if is_attack_c cm cw cand then begin
            let s = stops_c cm ~u t cand in
            if Aset.subset s !cur_stops then begin
              r := cand;
              cur_stops := s;
              changed := true
            end
          end
        end)
      sids
  done;
  !r

let prune m ~u t r = prune_c (make m) ~u t r

let clauses_c cm ~u t r =
  let up = Array.of_list (Aset.elements (Aset.diff u t)) in
  let n = Array.length up in
  if n > 16 then invalid_arg "Bounded.clauses: |U \\ T| > 16";
  let set_of mask =
    let s = ref Aset.empty in
    for i = 0 to n - 1 do
      if mask land (1 lsl i) <> 0 then s := Aset.add up.(i) !s
    done;
    !s
  in
  let d = ref [] in
  for mask = 0 to (1 lsl n) - 1 do
    if replay_c cm (cworld (cm.m.world (Aset.union t (set_of mask)))) r <> None then
      d := mask :: !d
  done;
  let d = !d in
  let maximal = List.filter (fun m -> not (List.exists (fun m' -> m' <> m && m land m' = m) d)) d in
  let full = (1 lsl n) - 1 in
  Clutter.sort (List.map (fun m -> set_of (full land lnot m)) maximal)

let clauses m ~u t r = clauses_c (make m) ~u t r

(* ---- search: hash-consed terms, interned knowledge ---------------------------------- *)

(* Terms are hash-consed to ints, so the intruder knowledge (an analysis-closed set of
   terms) is a set of ints and derivability needs no structural comparison. *)

module IS = Set.Make (Int)

type hc = {
  mutable kind : int array;  (* 0 name, 1 pair, 2 enc, 3 sig *)
  mutable left : int array;
  mutable right : int array;
  mutable inv : int array;  (* inverse key, -1 until computed *)
  mutable term : Term.t array;
  mutable n : int;
  names : (string, int) Hashtbl.t;
  nodes : (int, int) Hashtbl.t;  (* (kind, left, right) packed -> id *)
}

let hc_create () =
  {
    kind = Array.make 256 0;
    left = Array.make 256 0;
    right = Array.make 256 0;
    inv = Array.make 256 (-1);
    term = Array.make 256 (Term.Name "");
    n = 0;
    names = Hashtbl.create 64;
    nodes = Hashtbl.create 1024;
  }

let grow a n d = if n < Array.length a then a else Array.append a (Array.make (Array.length a) d)

let new_id h k l r t =
  let id = h.n in
  h.kind <- grow h.kind id 0;
  h.left <- grow h.left id 0;
  h.right <- grow h.right id 0;
  h.inv <- grow h.inv id (-1);
  h.term <- grow h.term id (Term.Name "");
  h.kind.(id) <- k;
  h.left.(id) <- l;
  h.right.(id) <- r;
  h.inv.(id) <- (if k = 0 then -1 else id);
  h.term.(id) <- t;
  h.n <- id + 1;
  if id >= 1 lsl 29 then failwith "Bounded: too many terms";
  id

let node h k l r =
  let key = (k lsl 60) lor (l lsl 30) lor r in
  match Hashtbl.find_opt h.nodes key with
  | Some id -> id
  | None ->
      let a = h.term.(l) and b = h.term.(r) in
      let t =
        match k with 1 -> Term.Pair (a, b) | 2 -> Term.Enc (a, b) | _ -> Term.Sig (a, b)
      in
      let id = new_id h k l r t in
      Hashtbl.add h.nodes key id;
      id

let rec of_term h = function
  | Term.Name s as t -> (
      match Hashtbl.find_opt h.names s with
      | Some id -> id
      | None ->
          let id = new_id h 0 0 0 t in
          Hashtbl.add h.names s id;
          id)
  | Term.Pair (a, b) -> node h 1 (of_term h a) (of_term h b)
  | Term.Enc (a, b) -> node h 2 (of_term h a) (of_term h b)
  | Term.Sig (a, b) -> node h 3 (of_term h a) (of_term h b)

let inverse_h h id =
  if h.inv.(id) >= 0 then h.inv.(id)
  else begin
    let j = of_term h (Term.inverse h.term.(id)) in
    h.inv.(id) <- j;
    j
  end

let rec synth_set h set m =
  IS.mem m set || (h.kind.(m) <> 0 && synth_set h set h.left.(m) && synth_set h set h.right.(m))

let analz_set h set ms =
  let s = ref set in
  let rec add t =
    if not (IS.mem t !s) then begin
      s := IS.add t !s;
      match h.kind.(t) with
      | 1 ->
          add h.left.(t);
          add h.right.(t)
      | 3 -> add h.right.(t)
      | _ -> ()
    end
  in
  List.iter add ms;
  let changed = ref true in
  while !changed do
    changed := false;
    IS.iter
      (fun t ->
        if
          h.kind.(t) = 2
          && (not (IS.mem h.right.(t) !s))
          && synth_set h !s (inverse_h h h.left.(t))
        then begin
          add h.right.(t);
          changed := true
        end)
      !s
  done;
  !s

let kadd h set m = if IS.mem m set then set else analz_set h set [ m ]

type hct = HT of int | HV of int | HN of int * hct * hct  (* HN (kind, l, r) *)

let rec hct_of h = function
  | CT t -> HT (of_term h t)
  | CV s -> HV s
  | CP (a, b) -> HN (1, hct_of h a, hct_of h b)
  | CE (a, b) -> HN (2, hct_of h a, hct_of h b)
  | CS (a, b) -> HN (3, hct_of h a, hct_of h b)

let rec inst_h h ah bind = function
  | HT id -> id
  | HV s -> ah.(bind.(s))
  | HN (k, a, b) -> node h k (inst_h h ah bind a) (inst_h h ah bind b)

type hworld = {
  hw : world;
  k0id : IS.t;
  k0set : Term.Set.t;
  auth_a : bool array;  (* by channel index *)
  conf_a : bool array;
  has_conf : bool;
}

type alt = { atom : Aset.elt; aw : hworld; own : bool }

type st = {
  pos : int array;
  bind : int array;
  flags : int;
  broken : int;  (* bit i: alt i no longer replays the run *)
  k : IS.t;  (* intruder knowledge, analysis-closed *)
  alt_k : IS.t array;
  sent : (int * int) list;  (* (channel index, message id) *)
  trace : event list;  (* reversed *)
}

let key c reduce st =
  let b = Buffer.create 64 in
  if not reduce then begin
    Array.iter (fun p -> Buffer.add_char b (Char.chr p)) st.pos;
    Array.iter (fun x -> Buffer.add_char b (Char.chr (x + 1))) st.bind
  end
  else begin
    (* strands outside symmetry groups in index order, then each group as a sorted list
       of its members' local states *)
    let local i =
      let l = Bytes.create (1 + Array.length c.strand_slots.(i)) in
      Bytes.set l 0 (Char.chr st.pos.(i));
      Array.iteri (fun k sl -> Bytes.set l (k + 1) (Char.chr (st.bind.(sl) + 1))) c.strand_slots.(i);
      Bytes.unsafe_to_string l
    in
    Array.iteri (fun i g -> if g < 0 then Buffer.add_string b (local i)) c.group;
    List.iter
      (fun members ->
        List.iter (Buffer.add_string b) (List.sort compare (List.map local members)))
      c.groups
  end;
  Buffer.add_int64_le b (Int64.of_int st.flags);
  Buffer.add_int64_le b (Int64.of_int st.broken);
  Buffer.contents b

let mask_to_set alts mask =
  let s = ref Aset.empty in
  Array.iteri (fun i a -> if mask land (1 lsl i) <> 0 then s := Aset.add a.atom !s) alts;
  !s

(* per compiled model: hash-consing state and compiled templates, shared by all calls *)
type engine = {
  h : hc;
  hsteps : hct array array;
  chan_idx : int array array;  (* per strand and step *)
  chans : chan option array;
}

let engines : (compiled * engine) list ref = ref []

let engine_of c =
  match List.assq_opt c !engines with
  | Some e -> e
  | None ->
      let h = hc_create () in
      let chans = ref [ None ] in
      let cidx ch =
        let rec find i = function
          | [] ->
              chans := !chans @ [ ch ];
              i
          | x :: r -> if x = ch then i else find (i + 1) r
        in
        find 0 !chans
      in
      let hsteps = Array.map (Array.map (fun st -> hct_of h st.cmsg)) c.steps in
      let chan_idx = Array.map (Array.map (fun st -> cidx st.cchan)) c.steps in
      let e = { h; hsteps; chan_idx; chans = Array.of_list !chans } in
      engines := (c, e) :: (if List.length !engines > 16 then [] else !engines);
      e

let hworld e (w : world) =
  let mem l = Array.map (function None -> false | Some ch -> List.mem ch l) e.chans in
  let k0id = analz_set e.h IS.empty (List.map (of_term e.h) w.k0) in
  {
    hw = w;
    k0id;
    k0set = Term.Set.of_list w.k0;
    auth_a = mem w.auth;
    conf_a = mem w.conf;
    has_conf = w.conf <> [];
  }

let can_receive_h e hijack w k sent ci m =
  let mem_sent () = List.exists (fun (c', m') -> c' = ci && m' = m) sent in
  if w.auth_a.(ci) then mem_sent ()
  else
    synth_set e.h k m
    || (w.has_conf && mem_sent ())
    || (hijack && List.exists (fun (_, m') -> m' = m) sent)

let search_c ?deadline ?(key_stops = true) ?(check_lattice = false) ?(reduce = false) cm ~u
    mode t =
  let key_stops = key_stops || mode = Least in
  let m = cm.m in
  let e = engine_of cm in
  let h = e.h in
  let cw = hworld e (m.world t) in
  let alts =
    Array.of_list
      (List.map
         (fun a ->
           let aw = hworld e (m.world (Aset.add a t)) in
           let own =
             (not (Term.Set.equal aw.k0set cw.k0set))
             || List.sort compare aw.hw.conf <> List.sort compare cw.hw.conf
           in
           { atom = a; aw; own })
         (Aset.elements (Aset.diff u t)))
  in
  if Array.length alts > 62 then invalid_arg "Bounded.search: |U \\ T| > 62";
  let states = ref 0 and attack_states = ref 0 and nonprincipal = ref 0 in
  let best = ref None in
  let check_deadline () =
    match deadline with
    | Some d when !states land 1023 = 0 && Unix.gettimeofday () > d -> raise Timeout
    | _ -> ()
  in
  let exception Found of run in
  let search_scenario (sc : scenario) =
    let bind0 = Array.make cm.nslots (-1) in
    fix_scenario cm sc bind0;
    let c = cm in
    let ah = Array.map (of_term h) c.atoms in
    let nstr = Array.length c.steps in
    let broken0 = ref 0 in
    Array.iteri
      (fun i a ->
        if List.for_all (fun s -> s.sname <> sc.sname) a.aw.hw.scenarios then
          broken0 := !broken0 lor (1 lsl i))
      alts;
    let init =
      {
        pos = Array.make nstr 0;
        bind = bind0;
        flags = 0;
        broken = !broken0;
        k = cw.k0id;
        alt_k = Array.map (fun a -> if a.own then a.aw.k0id else IS.empty) alts;
        sent = [];
        trace = [];
      }
    in
    (* successors of state [s] by step [p] of strand [i], in push order *)
    let succ_step s i p =
      let st = c.steps.(i).(p) in
      let ci = e.chan_idx.(i).(p) in
      let npos = Array.copy s.pos in
      npos.(i) <- p + 1;
      match st.cdir with
      | Send ->
          let mid = inst_h h ah s.bind e.hsteps.(i).(p) in
          let ev = { edir = Send; strand = i; step = p; echan = st.cchan; msg = h.term.(mid) } in
          let k = if cw.conf_a.(ci) then s.k else kadd h s.k mid in
          let alt_k =
            Array.mapi
              (fun j a ->
                if a.own && s.broken land (1 lsl j) = 0 && not a.aw.conf_a.(ci) then
                  kadd h s.alt_k.(j) mid
                else s.alt_k.(j))
              alts
          in
          let flags = m.goal.update (view_of c npos s.bind s.flags) ev in
          [
            {
              pos = npos;
              bind = s.bind;
              flags;
              broken = s.broken;
              k;
              alt_k;
              sent = (ci, mid) :: s.sent;
              trace = ev :: s.trace;
            };
          ]
      | Recv ->
          let free = List.filter (fun sl -> s.bind.(sl) < 0) st.cvars in
          let out = ref [] in
          let rec assign bind = function
            | [] ->
                let mid = inst_h h ah bind e.hsteps.(i).(p) in
                if can_receive_h e m.hijack cw s.k s.sent ci mid then begin
                  let broken = ref s.broken in
                  Array.iteri
                    (fun j a ->
                      if !broken land (1 lsl j) = 0 then
                        let k = if a.own then s.alt_k.(j) else s.k in
                        if not (can_receive_h e m.hijack a.aw k s.sent ci mid) then
                          broken := !broken lor (1 lsl j))
                    alts;
                  let ev =
                    { edir = Recv; strand = i; step = p; echan = st.cchan; msg = h.term.(mid) }
                  in
                  let flags = m.goal.update (view_of c npos bind s.flags) ev in
                  out :=
                    {
                      pos = npos;
                      bind;
                      flags;
                      broken = !broken;
                      k = s.k;
                      alt_k = s.alt_k;
                      sent = s.sent;
                      trace = ev :: s.trace;
                    }
                    :: !out
                end
            | sl :: rest ->
                Array.iter
                  (fun vi ->
                    let b = Array.copy bind in
                    b.(sl) <- vi;
                    assign b rest)
                  c.value_idx
          in
          assign s.bind free;
          List.rev !out
    in
    let seen = Hashtbl.create 4096 in
    let stack = ref [ init ] in
    let push s = stack := s :: !stack in
    while !stack <> [] do
      let s = List.hd !stack in
      stack := List.tl !stack;
      let k = key cm reduce (if key_stops then s else { s with broken = 0 }) in
      if not (Hashtbl.mem seen k) then begin
        Hashtbl.add seen k ();
        incr states;
        check_deadline ();
        let v = view_of c s.pos s.bind s.flags in
        if m.goal.violated v then begin
          incr attack_states;
          let run = { scenario = sc.sname; events = List.rev s.trace } in
          match mode with
          | As_found | Pruned -> raise (Found run)
          | Least ->
              let stops = mask_to_set alts s.broken in
              if check_lattice && List.length (clauses_c cm ~u t run) > 1 then
                incr nonprincipal;
              (match !best with
              | Some (_, b) when Aset.compare_size_lex b stops <= 0 -> ()
              | _ -> best := Some (run, stops));
              if Aset.is_empty stops && not check_lattice then raise (Found run)
        end
        else
          for i = 0 to nstr - 1 do
            let p = s.pos.(i) in
            let len = Array.length c.steps.(i) in
            if p < len then
              if not reduce then List.iter push (succ_step s i p)
              else begin
                (* the block: receives up to and including the next send *)
                let q = ref p in
                while !q < len - 1 && c.steps.(i).(!q).cdir = Recv do
                  incr q
                done;
                let states = ref [ s ] in
                for j = p to !q do
                  states := List.concat_map (fun s -> succ_step s i j) !states
                done;
                List.iter push !states
              end
          done
      end
    done
  in
  let outcome =
    try
      List.iter search_scenario cw.hw.scenarios;
      match !best with None -> Achieves | Some (run, s) -> Attack { run; stops = s }
    with Found run -> Attack { run; stops = Aset.empty }
  in
  let outcome =
    match outcome with
    | Achieves -> Achieves
    | Attack { run; stops = tracked } ->
        let run = if mode = Pruned then prune_c cm ~u t run else run in
        let stops = stops_c cm ~u t run in
        (* in Least mode the stopping set tracked during the search must equal replay *)
        if mode = Least && not (Aset.equal tracked stops) then
          failwith
            (Format.asprintf "Bounded.search: tracked stops %a <> replayed %a" Aset.pp tracked
               Aset.pp stops);
        Attack { run; stops }
  in
  { outcome; states = !states; attack_states = !attack_states; nonprincipal = !nonprincipal }

let search ?deadline ?key_stops ?check_lattice ?reduce m ~u mode t =
  search_c ?deadline ?key_stops ?check_lattice ?reduce (make m) ~u mode t

(* ---- oracle ------------------------------------------------------------------------ *)

type counter = {
  mutable calls : int;
  mutable states : int;
  mutable max_states : int;
  mutable time : float;
  mutable nonprincipal : int;
}

let counter () = { calls = 0; states = 0; max_states = 0; time = 0.; nonprincipal = 0 }

let pp_term = Term.pp

let pp_event fmt e =
  Format.fprintf fmt "%s %a%s"
    (match e.edir with Send -> "send" | Recv -> "recv")
    pp_term e.msg
    (match e.echan with None -> "" | Some (a, b) -> Printf.sprintf " on %s->%s" a b)

let pp_run m fmt r =
  Format.fprintf fmt "[%s] " r.scenario;
  Format.pp_print_list
    ~pp_sep:(fun f () -> Format.pp_print_string f "; ")
    (fun f e -> Format.fprintf f "%s %a" m.strands.(e.strand).label pp_event e)
    fmt r.events

let oracle ?deadline ?key_stops ?reduce ?counter m ~u mode =
  let cm = make m in
  fun t ->
    let t0 = Unix.gettimeofday () in
    let r = search_c ?deadline ?key_stops ?reduce cm ~u mode t in
    (match counter with
    | None -> ()
    | Some c ->
        c.calls <- c.calls + 1;
        c.states <- c.states + r.states;
        c.max_states <- max c.max_states r.states;
        c.time <- c.time +. (Unix.gettimeofday () -. t0);
        match r.outcome with
        | Attack { run; _ }
          when Aset.cardinal (Aset.diff u t) <= 12 && List.length (clauses_c cm ~u t run) > 1 ->
            c.nonprincipal <- c.nonprincipal + 1
        | _ -> ());
    match r.outcome with
    | Achieves -> Loop.Achieves
    | Attack { run; stops } ->
        Loop.Fails { stops; descr = Format.asprintf "%a" (pp_run m) run }
