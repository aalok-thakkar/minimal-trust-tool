let atom i =
  if i < 0 || i > 99 then invalid_arg "Synth.atom";
  Printf.sprintf "Non(k_%02d)" i

let index a =
  match Scanf.sscanf_opt a "Non(k_%2d)%!" (fun i -> i) with
  | Some i when atom i = a -> i
  | _ -> invalid_arg ("Synth.index: " ^ a)

let universe n = Aset.of_list (List.init n atom)
let of_indices l = Clutter.minimalize (List.map (fun e -> Aset.of_list (List.map atom e)) l)

(* k distinct elements of 0..n-1, uniformly: a partial Fisher-Yates shuffle *)
let sample rng n k =
  let a = Array.init n (fun i -> i) in
  for i = 0 to k - 1 do
    let j = i + Random.State.int rng (n - i) in
    let t = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- t
  done;
  Array.to_list (Array.sub a 0 k)

let random rng ~n ~m =
  let kmax = min 3 n in
  of_indices
    (List.init m (fun _ ->
         let k = 1 + Random.State.int rng kmax in
         sample rng n k))

let random_state ~family ~n ~m ~seed =
  Random.State.make
    (Array.append [| 2026; n; m; seed |]
       (Array.init (String.length family) (fun i -> Char.code family.[i])))

let disjoint_pairs n = of_indices (List.init (n / 2) (fun i -> [ 2 * i; (2 * i) + 1 ]))

let dual_pairs n =
  let rec go i =
    if i = n / 2 then [ [] ]
    else
      let rest = go (i + 1) in
      List.concat_map (fun r -> [ (2 * i) :: r; ((2 * i) + 1) :: r ]) rest
  in
  of_indices (go 0)

let threshold ~s ~k =
  if k < 1 || k > s then invalid_arg "Synth.threshold";
  let rec subsets k i =
    if k = 0 then [ [] ]
    else if i >= s then []
    else List.map (fun r -> i :: r) (subsets (k - 1) (i + 1)) @ subsets k (i + 1)
  in
  of_indices (subsets k 0)

let achieves h t = Clutter.is_transversal t h

let hypergraph_oracle h t =
  match List.find_opt (fun e -> Aset.disjoint t e) h with
  | None -> Loop.Achieves
  | Some e -> Loop.Fails { stops = e; descr = "edge " ^ Aset.to_string e }

let padded_oracle ?extra rng ~u h t =
  match List.find_opt (fun e -> Aset.disjoint t e) h with
  | None -> Loop.Achieves
  | Some e ->
      let free = Aset.diff u (Aset.union t e) in
      let pad =
        match extra with
        | None -> Aset.filter (fun _ -> Random.State.bool rng) free
        | Some k ->
            let a = Array.of_list (Aset.elements free) in
            let k = min k (Array.length a) in
            List.fold_left (fun acc i -> Aset.add a.(i) acc) Aset.empty
              (sample rng (Array.length a) k)
      in
      Loop.Fails { stops = Aset.union e pad; descr = "padded edge " ^ Aset.to_string e }
