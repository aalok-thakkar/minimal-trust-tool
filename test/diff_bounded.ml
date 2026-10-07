(* Differential test of Bounded/Protocols against the Python prototype: prints the lines
   that test/diff_bounded.py prints (see there), from the OCaml library. *)

open Trust
module P = Protocols

let fmt_set s = "{" ^ String.concat "," (Aset.elements s) ^ "}"
let fmt_fam f = "[" ^ String.concat ";" (List.map fmt_set (Clutter.sort f)) ^ "]"

let subsets u =
  let atoms = Aset.elements u in
  let n = List.length atoms in
  List.init (1 lsl n) (fun mask ->
      Aset.of_list (List.filteri (fun j _ -> mask land (1 lsl j) <> 0) atoms))

let mode_str = function
  | Bounded.As_found -> "as_found"
  | Bounded.Pruned -> "pruned"
  | Bounded.Least -> "least"

let emit (row : P.row) mode ~counted =
  let m = row.model row.default_pool in
  List.iter
    (fun t ->
      let r = Bounded.search ~key_stops:row.key_stops m ~u:row.u mode t in
      Printf.printf "TRUST %s %s %s %s %s\n" row.id (mode_str mode) (fmt_set t)
        (match r.outcome with Bounded.Achieves -> "ACH" | Bounded.Attack a -> fmt_set a.stops)
        (if counted then string_of_int r.states else "-"))
    (subsets row.u);
  List.iter
    (fun shrink ->
      let w, h, st = Loop.weakest ~shrink ~u:row.u (P.oracle row mode) in
      Printf.printf "LOOP %s %s %s %s %s %d %d %d\n" row.id (mode_str mode)
        (if shrink then "shrink" else "plain")
        (fmt_fam w) (fmt_fam h) st.distinct st.queries st.shrink_calls)
    [ false; true ]

let () =
  List.iter
    (fun row ->
      emit row Bounded.Pruned ~counted:true;
      emit row Bounded.As_found ~counted:true)
    [ P.signed_cr; P.two_key; P.signed_nonames; P.shared_nonames ];
  List.iter (fun row -> emit row Bounded.As_found ~counted:true) [ P.nspk; P.nsl ];
  List.iter
    (fun row -> emit row Bounded.Least ~counted:false)
    [ P.nspk_keys_least; P.nsl_keys_least; P.nspk_channels; P.nsl_channels;
      P.nspk_channels_hijack; P.nsl_channels_hijack ];
  List.iter
    (fun v ->
      List.iter
        (fun (part, goals) -> emit (P.composition v part goals) Bounded.Least ~counted:false)
        [ (P.P1, P.Chi1); (P.P2, P.Chi2); (P.Both, P.Chi1); (P.Both, P.Chi2);
          (P.Both, P.Chi1_and_chi2) ])
    [ P.Tagged; P.Untagged ]
