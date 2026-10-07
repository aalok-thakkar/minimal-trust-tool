(* trust: command-line entry point. Subcommands:
     selftest   quick checks of the core library (Section 2 answers, blocker
                involution, Dolev-Yao derivability). *)

open Trust

let fam l = List.map Aset.of_list l

let selftest () =
  let ok = ref true in
  let check name c =
    Printf.printf "%-48s %s\n" name (if c then "ok" else "FAIL");
    if not c then ok := false
  in
  let ska = "Non(sk_A)" and unq = "Unq(N)" and k1 = "Non(k1)" and k2 = "Non(k2)" in
  let fails l = Loop.Fails { stops = Aset.of_list l; descr = "" } in
  let signed t =
    if not (Aset.mem ska t) then fails [ ska ]
    else if not (Aset.mem unq t) then fails [ unq ]
    else Loop.Achieves
  in
  let w, h, st = Loop.weakest ~u:(Aset.of_list [ ska; unq ]) signed in
  Format.printf "signed CR: W = %a, H = %a, %a@." Clutter.pp_family w Clutter.pp_family h
    Loop.pp_stats st;
  check "signed CR: W = {{Non(sk_A), Unq(N)}}"
    (Clutter.equal_family w (fam [ [ ska; unq ] ]));
  let twokey t =
    if (not (Aset.mem k1 t)) && not (Aset.mem k2 t) then fails [ k1; k2 ]
    else if not (Aset.mem unq t) then fails [ unq ]
    else Loop.Achieves
  in
  let w, h, st = Loop.weakest ~u:(Aset.of_list [ k1; k2; unq ]) twokey in
  Format.printf "two-key:   W = %a, H = %a, %a@." Clutter.pp_family w Clutter.pp_family h
    Loop.pp_stats st;
  check "two-key: W = {{Non(k1), Unq(N)}, {Non(k2), Unq(N)}}"
    (Clutter.equal_family w (fam [ [ k1; unq ]; [ k2; unq ] ]));
  let h = fam [ [ "a"; "b" ]; [ "a"; "c" ]; [ "b"; "c" ] ] in
  check "blocker involution on the triangle"
    (Clutter.equal_family (Clutter.blocker (Clutter.blocker h)) h);
  let open Term in
  let kab = name "k_AB" and m = name "m" in
  check "Dolev-Yao: {k, enc(k, m)} derives m" (Dy.derivable [ kab; enc kab m ] m);
  check "Dolev-Yao: {pk_A, enc(pk_A, m)} does not derive m"
    (not (Dy.derivable [ name "pk_A"; enc (name "pk_A") m ] m));
  if !ok then print_endline "selftest: all checks passed"
  else (
    print_endline "selftest: FAILED";
    exit 1)

let usage () =
  prerr_endline "usage: trust selftest";
  prerr_endline "       trust scale [--quick] [--phase counts,gadget,timing] [--jobs N] [--timeout S] [--out DIR]";
  prerr_endline "       trust cpsa [--protocols DIR] [--out DIR] [--only NAME,...] [--reps N] [--no-timing] [--timeout S]";
  exit 2

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "selftest" ] -> selftest ()
  | "scale" :: args -> Scale_driver.main args
  | "cpsa" :: args -> Cpsa_driver.main args
  | _ -> usage ()
