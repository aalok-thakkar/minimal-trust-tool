type atom = string

include Set.Make (String)

let compare_size_lex a b =
  let c = Int.compare (cardinal a) (cardinal b) in
  if c <> 0 then c else compare a b

let pp fmt s =
  Format.fprintf fmt "{%s}" (String.concat ", " (elements s))

let to_string s = Format.asprintf "%a" pp s
