(* Differential test against the Python reference. Reads the output of
   test/diff_driver.py on stdin, recomputes every result with the OCaml library, and
   compares families as sets and call counts exactly (both sides use the same
   candidate order and the same oracles). Exit status 1 on any disagreement. *)

open Trust

let words l = List.filter (( <> ) "") (String.split_on_char ' ' l)

type case = {
  id : int;
  loop : bool;
  u : Aset.t;
  fams : (string * Aset.t list) list;
  stats : (string * int list) list;
}

let read_cases ic =
  let next () = In_channel.input_line ic in
  let rec read_fam k acc =
    if k = 0 then List.rev acc
    else
      match next () with
      | Some l -> (
          match words l with
          | "S" :: atoms -> read_fam (k - 1) (Aset.of_list atoms :: acc)
          | _ -> failwith ("bad set line: " ^ l))
      | None -> failwith "eof in family"
  in
  let rec read_body c =
    match Option.map words (next ()) with
    | Some [ "END" ] -> { c with fams = List.rev c.fams; stats = List.rev c.stats }
    | Some ("U" :: atoms) -> read_body { c with u = Aset.of_list atoms }
    | Some [ "FAM"; tag; k ] ->
        let f = read_fam (int_of_string k) [] in
        read_body { c with fams = (tag, f) :: c.fams }
    | Some ("STAT" :: tag :: nums) ->
        read_body { c with stats = (tag, List.map int_of_string nums) :: c.stats }
    | _ -> failwith "bad case body"
  in
  let rec go acc =
    match Option.map words (next ()) with
    | None -> List.rev acc
    | Some [ "CASE"; id; loop ] ->
        let c =
          read_body
            { id = int_of_string id; loop = loop = "1"; u = Aset.empty; fams = []; stats = [] }
        in
        go (c :: acc)
    | Some [] -> go acc
    | Some _ -> failwith "expected CASE"
  in
  go []

let first_unhit a t = List.find_opt (fun e -> not (Clutter.hits t e)) a

let () =
  let cases = read_cases stdin in
  let bad = ref 0 and nblock = ref 0 and nloop = ref 0 in
  let fail c what =
    incr bad;
    Printf.printf "MISMATCH case %d: %s\n%!" c.id what
  in
  List.iter
    (fun c ->
      let fam tag = List.assoc tag c.fams in
      let h = fam "H" in
      incr nblock;
      if not (Clutter.equal_family (Clutter.blocker h) (fam "B")) then fail c "blocker";
      if c.loop then begin
        incr nloop;
        let a = Clutter.minimalize h in
        let minimal t =
          match first_unhit a t with
          | None -> Loop.Achieves
          | Some e -> Loop.Fails { stops = e; descr = "" }
        in
        let padded t =
          match first_unhit a t with
          | None -> Loop.Achieves
          | Some e ->
              let rest = Aset.diff (Aset.diff c.u t) e in
              let stops =
                match Aset.min_elt_opt rest with Some x -> Aset.add x e | None -> e
              in
              Loop.Fails { stops; descr = "" }
        in
        let w, hh, st = Loop.weakest ~u:c.u minimal in
        if not (Clutter.equal_family w (fam "W")) then fail c "W (minimal)";
        if not (Clutter.equal_family hh (fam "HH")) then fail c "H (minimal)";
        if [ st.distinct; st.queries; st.shrink_calls ] <> List.assoc "min" c.stats then
          fail c
            (Printf.sprintf "stats (minimal): ocaml %d %d %d" st.distinct st.queries
               st.shrink_calls);
        let w2, h2, st2 = Loop.weakest ~shrink:true ~u:c.u padded in
        if not (Clutter.equal_family w2 (fam "W2")) then fail c "W (shrink)";
        if not (Clutter.equal_family h2 (fam "H2")) then fail c "H (shrink)";
        if [ st2.distinct; st2.queries; st2.shrink_calls ] <> List.assoc "shrink" c.stats
        then
          fail c
            (Printf.sprintf "stats (shrink): ocaml %d %d %d" st2.distinct st2.queries
               st2.shrink_calls)
      end)
    cases;
  Printf.printf
    "differential test: %d cases (blocker compared on %d, Loop minimal and padded+shrink \
     on %d): %d mismatches\n"
    (List.length cases) !nblock !nloop !bad;
  if !bad > 0 then exit 1
