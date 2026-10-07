type t = Name of string | Pair of t * t | Enc of t * t | Sig of t * t

let name s = Name s
let pair a b = Pair (a, b)
let enc k m = Enc (k, m)
let sign k m = Sig (k, m)

let starts_with ~prefix s =
  String.length s >= String.length prefix
  && String.sub s 0 (String.length prefix) = prefix

let inverse = function
  | Name s when starts_with ~prefix:"pk_" s -> Name ("sk_" ^ String.sub s 3 (String.length s - 3))
  | Name s when starts_with ~prefix:"sk_" s -> Name ("pk_" ^ String.sub s 3 (String.length s - 3))
  | k -> k

let compare : t -> t -> int = Stdlib.compare
let equal a b = compare a b = 0

module Set = Set.Make (struct
  type nonrec t = t

  let compare = compare
end)

let subterms t =
  let rec go acc t =
    let acc = Set.add t acc in
    match t with
    | Name _ -> acc
    | Pair (a, b) | Enc (a, b) | Sig (a, b) -> go (go acc a) b
  in
  go Set.empty t

let rec pp fmt = function
  | Name s -> Format.pp_print_string fmt s
  | Pair (a, b) -> Format.fprintf fmt "<%a, %a>" pp a pp b
  | Enc (k, m) -> Format.fprintf fmt "{%a}_%a" pp m pp k
  | Sig (k, m) -> Format.fprintf fmt "[%a]_%a" pp m pp k

let to_string t = Format.asprintf "%a" pp t
