open Term

let universe terms =
  let u = List.fold_left (fun acc t -> Set.union acc (subterms t)) Set.empty terms in
  Set.fold (fun t acc -> Set.add (inverse t) acc) u u

let size t =
  let rec go = function
    | Name _ -> 1
    | Pair (a, b) | Enc (a, b) | Sig (a, b) -> 1 + go a + go b
  in
  go t

(* Decompose to a fixpoint. Decryption depends on keys, which later steps can add, so
   iterate until nothing changes. *)
let rec decompose k =
  let k' =
    Set.fold
      (fun t acc ->
        match t with
        | Name _ -> acc
        | Pair (a, b) -> Set.add a (Set.add b acc)
        | Sig (_, m) -> Set.add m acc
        | Enc (key, m) -> if Set.mem (inverse key) acc then Set.add m acc else acc)
      k k
  in
  if Set.cardinal k' = Set.cardinal k then k else decompose k'

(* One composition pass over the compound members of the universe, smallest first, so
   that a term whose components are composed in the same pass is also found. *)
let compose compounds k =
  List.fold_left
    (fun acc t ->
      if Set.mem t acc then acc
      else
        match t with
        | Pair (a, b) | Enc (a, b) | Sig (a, b) ->
            if Set.mem a acc && Set.mem b acc then Set.add t acc else acc
        | Name _ -> acc)
    k compounds

let closure known univ =
  let compounds =
    Set.elements univ
    |> List.filter (function Name _ -> false | _ -> true)
    |> List.stable_sort (fun a b -> Int.compare (size a) (size b))
  in
  let rec fix k =
    let k' = compose compounds (decompose k) in
    if Set.cardinal k' = Set.cardinal k then k else fix k'
  in
  fix known

let derivable known target =
  let univ = universe (target :: known) in
  Set.mem target (closure (Set.of_list known) univ)
