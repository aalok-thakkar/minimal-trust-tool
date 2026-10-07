type family = Aset.t list

let sort fam = List.sort_uniq Aset.compare_size_lex fam
let hits t e = not (Aset.disjoint t e)
let is_transversal t h = List.for_all (hits t) h

(* Inverted index from atoms to ids of kept sets, plus a counter per kept set. A kept
   set [t] is contained in [s] iff, after counting over the atoms of [s], the counter of
   [t] reaches [|t|]. Sets arrive by increasing size and duplicates are removed by
   [sort], so only kept sets of strictly smaller size can be contained in [s]; a kept
   set enters the index only once a larger set arrives. A family of equal-size sets
   therefore costs nothing beyond the sort. *)
let minimalize fam =
  match sort fam with
  | [] -> []
  | s0 :: _ when Aset.is_empty s0 -> [ s0 ]
  | sorted ->
      let n = List.length sorted in
      let size = Array.make n 0 and count = Array.make n 0 in
      let index : (string, int list) Hashtbl.t = Hashtbl.create 64 in
      let find x = Option.value ~default:[] (Hashtbl.find_opt index x) in
      let next = ref 0 and kept = ref [] in
      let pending = ref [] and pending_size = ref 0 in
      let flush () =
        List.iter
          (fun (id, s) -> Aset.iter (fun x -> Hashtbl.replace index x (id :: find x)) s)
          !pending;
        pending := []
      in
      List.iter
        (fun s ->
          let k = Aset.cardinal s in
          if k > !pending_size then (
            flush ();
            pending_size := k);
          let touched = ref [] and subsumed = ref false in
          (try
             Aset.iter
               (fun x ->
                 List.iter
                   (fun id ->
                     if count.(id) = 0 then touched := id :: !touched;
                     count.(id) <- count.(id) + 1;
                     if count.(id) = size.(id) then (
                       subsumed := true;
                       raise Exit))
                   (find x))
               s
           with Exit -> ());
          List.iter (fun id -> count.(id) <- 0) !touched;
          if not !subsumed then (
            let id = !next in
            incr next;
            size.(id) <- k;
            pending := (id, s) :: !pending;
            kept := s :: !kept))
        sorted;
      List.rev !kept

(* One Berge step: the minimal transversals of [h @ [e]] from the clutter [cur] of
   minimal transversals of [h]. Parts that meet [e] stay. A part [p] missing [e] is
   replaced by [p + a] for each [a] in [e]. The result is already a clutter, so no
   general minimalisation pass is needed:
   - two extensions [p + a], [q + b] with [p + a] a subset of [q + b] force [a = b]
     and [p] a subset of [q] (both [p], [q] miss [e]), so [p = q] since [cur] is a
     clutter; extensions are pairwise incomparable and distinct;
   - a staying part [q] cannot contain an extension [p + a] (it would contain [p]);
   - an extension [p + a] contains a staying part [q] iff [q \ p = {a}] (since [p]
     contains no member of [cur]); then [a] is in [e] because [q] meets [e] and [p]
     does not. Such [q] are found by counting [|q inter p|] through an inverted index
     of the staying parts: [q] blocks [a] iff the count reaches [|q| - 1].
   So each step equals [minimalize] of the textbook step. *)
let berge_step cur e =
  let stay, miss = List.partition (fun p -> hits p e) cur in
  let stay = Array.of_list stay in
  let ns = Array.length stay in
  let size = Array.map Aset.cardinal stay and count = Array.make ns 0 in
  let index : (string, int list) Hashtbl.t = Hashtbl.create 64 in
  let always = ref Aset.empty in
  Array.iteri
    (fun id q ->
      if size.(id) = 1 then always := Aset.union q !always
      else
        Aset.iter
          (fun x ->
            Hashtbl.replace index x
              (id :: Option.value ~default:[] (Hashtbl.find_opt index x)))
          q)
    stay;
  let e_open = Aset.diff e !always in
  let ext =
    List.concat_map
      (fun p ->
        let touched = ref [] in
        Aset.iter
          (fun x ->
            List.iter
              (fun id ->
                if count.(id) = 0 then touched := id :: !touched;
                count.(id) <- count.(id) + 1)
              (Option.value ~default:[] (Hashtbl.find_opt index x)))
          p;
        let blocked =
          List.fold_left
            (fun acc id ->
              let b =
                if count.(id) = size.(id) - 1 then Aset.union acc (Aset.diff stay.(id) p)
                else acc
              in
              count.(id) <- 0;
              b)
            Aset.empty !touched
        in
        Aset.fold (fun a acc -> Aset.add a p :: acc) (Aset.diff e_open blocked) [])
      miss
  in
  Array.to_list stay @ ext

let blocker h =
  let h = minimalize h in
  if List.exists Aset.is_empty h then []
  else sort (List.fold_left berge_step [ Aset.empty ] h)

let equal_family a b = List.equal Aset.equal (sort a) (sort b)

let pp_family fmt fam =
  Format.fprintf fmt "[%s]" (String.concat ", " (List.map Aset.to_string (sort fam)))
