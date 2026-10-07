type witness = { stops : Aset.t; descr : string }
type answer = Achieves | Fails of witness

type stats = {
  distinct : int;
  queries : int;
  shrink_calls : int;
  oracle_time : float;
  blocker_time : float;
  iterations : int;
}

exception Unsound_witness of string

module Amap = Map.Make (Aset)

let unsound fmt = Format.kasprintf (fun s -> raise (Unsound_witness s)) fmt

let weakest ?(shrink = false) ~u oracle =
  let memo = ref Amap.empty in
  let distinct = ref 0 and queries = ref 0 and shrink_calls = ref 0 in
  let oracle_time = ref 0. and blocker_time = ref 0. and iterations = ref 0 in
  let ask t =
    match Amap.find_opt t !memo with
    | Some r -> r
    | None ->
        incr distinct;
        let t0 = Unix.gettimeofday () in
        let r = oracle t in
        oracle_time := !oracle_time +. (Unix.gettimeofday () -. t0);
        (match r with
        | Fails w when not (Aset.subset w.stops u) ->
            unsound "witness %a (%s) for trust %a is not a subset of U = %a" Aset.pp
              w.stops w.descr Aset.pp t Aset.pp u
        | Fails w when not (Aset.disjoint w.stops t) ->
            unsound "witness %a (%s) meets the trust %a it fails" Aset.pp w.stops
              w.descr Aset.pp t
        | _ -> ());
        memo := Amap.add t r !memo;
        r
  in
  let blocker h =
    let t0 = Unix.gettimeofday () in
    let c = Clutter.blocker h in
    blocker_time := !blocker_time +. (Unix.gettimeofday () -. t0);
    c
  in
  let shrink_stops s =
    let before = !distinct in
    let cur = ref s in
    Aset.iter
      (fun a ->
        if Aset.mem a !cur then
          let rest = Aset.remove a !cur in
          let trial = Aset.diff u rest in
          match ask trial with
          | Achieves -> ()
          | Fails w ->
              if not (Aset.subset w.stops rest) then
                unsound "shrink: witness %a (%s) for trust %a is not inside %a" Aset.pp
                  w.stops w.descr Aset.pp trial Aset.pp rest;
              cur := w.stops)
      s;
    shrink_calls := !shrink_calls + (!distinct - before);
    !cur
  in
  let rec loop h =
    incr iterations;
    let c = blocker h in
    let rec scan = function
      | [] -> (c, h)
      | t :: rest -> (
          incr queries;
          match ask t with
          | Achieves -> scan rest
          | Fails w ->
              (match List.find_opt (fun e -> Aset.subset e w.stops) h with
              | Some e ->
                  unsound "witness %a (%s) for candidate %a contains %a, already in H"
                    Aset.pp w.stops w.descr Aset.pp t Aset.pp e
              | None -> ());
              let s = if shrink then shrink_stops w.stops else w.stops in
              (* [h] is a clutter and [s] contains none of its members (checked above;
                 shrinking only removes atoms), so minimalising [s :: h] amounts to
                 dropping the members that contain [s]. *)
              loop (Clutter.sort (s :: List.filter (fun e -> not (Aset.subset s e)) h)))
    in
    scan c
  in
  let w, h = loop [] in
  ( w,
    h,
    {
      distinct = !distinct;
      queries = !queries;
      shrink_calls = !shrink_calls;
      oracle_time = !oracle_time;
      blocker_time = !blocker_time;
      iterations = !iterations;
    } )

let brute_force ~u pred =
  let atoms = Array.of_list (Aset.elements u) in
  let n = Array.length atoms in
  if n > 30 then invalid_arg "Loop.brute_force: |u| > 30";
  let set_of mask =
    let s = ref Aset.empty in
    for i = 0 to n - 1 do
      if mask land (1 lsl i) <> 0 then s := Aset.add atoms.(i) !s
    done;
    !s
  in
  let suff = Bytes.make (1 lsl n) '\000' in
  for mask = 0 to (1 lsl n) - 1 do
    if pred (set_of mask) then Bytes.set suff mask '\001'
  done;
  let is_suff m = Bytes.get suff m = '\001' in
  let out = ref [] in
  for mask = 0 to (1 lsl n) - 1 do
    if is_suff mask then begin
      let minimal = ref true in
      for i = 0 to n - 1 do
        if mask land (1 lsl i) <> 0 && is_suff (mask lxor (1 lsl i)) then minimal := false
      done;
      if !minimal then out := set_of mask :: !out
    end
  done;
  Clutter.sort !out

type levelwise_result = { found : Aset.t list; calls : int; complete : bool }

exception Budget

let levelwise ?(budget = max_int) ~u pred =
  let atoms = Array.of_list (Aset.elements u) in
  let n = Array.length atoms in
  let found = ref [] and calls = ref 0 in
  let visit s =
    if not (List.exists (fun f -> Aset.subset f s) !found) then begin
      if !calls >= budget then raise Budget;
      incr calls;
      if pred s then found := s :: !found
    end
  in
  (* k-subsets of atoms.(i..), in lexicographic order, added to [acc] *)
  let rec combos k i acc =
    if k = 0 then visit acc
    else
      for j = i to n - k do
        combos (k - 1) (j + 1) (Aset.add atoms.(j) acc)
      done
  in
  let complete =
    try
      for k = 0 to n do
        combos k 0 Aset.empty
      done;
      true
    with Budget -> false
  in
  { found = Clutter.sort !found; calls = !calls; complete }

let greedy_rgl ~u pred =
  if not (pred u) then (None, 1)
  else
    let t, calls =
      Aset.fold
        (fun a (t, calls) ->
          let t' = Aset.remove a t in
          if pred t' then (t', calls + 1) else (t, calls + 1))
        u (u, 1)
    in
    (Some t, calls)

let pp_stats fmt s =
  Format.fprintf fmt
    "distinct=%d queries=%d shrink_calls=%d iterations=%d oracle_time=%.6fs \
     blocker_time=%.6fs"
    s.distinct s.queries s.shrink_calls s.iterations s.oracle_time s.blocker_time
