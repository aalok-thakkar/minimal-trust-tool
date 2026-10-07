open Term

let key_of_atom a = name (Printf.sprintf "k_%02d" (Synth.index a))

let term s j nonce =
  Aset.fold
    (fun a t -> enc (key_of_atom a) t)
    s
    (pair nonce (name (Printf.sprintf "tag_%d" j)))

type event = Send of Term.t | Recv of Term.t

let oracle ~n h =
  let edges = Array.of_list h in
  let m = Array.length edges in
  let nonce = Array.init m (fun j -> name (Printf.sprintf "N_%d" j)) in
  (* t.(j).(l) = t_j(N_l) *)
  let t = Array.init m (fun j -> Array.init m (fun l -> term edges.(j) j nonce.(l))) in
  let public =
    name "A"
    :: List.concat (List.init m (fun j -> [ name (Printf.sprintf "B_%d" j); name (Printf.sprintf "tag_%d" j) ]))
  in
  fun trust ->
    let k0 =
      public
      @ List.filter_map
          (fun i ->
            if Aset.mem (Synth.atom i) trust then None
            else Some (name (Printf.sprintf "k_%02d" i)))
          (List.init n Fun.id)
    in
    (* knowledge of a state: k0, N_j once B_j has sent, t_j(N_bind) once A_j has sent *)
    let sent pos bind =
      List.concat
        (List.init m (fun j ->
             (if pos.(2 * j) >= 1 then [ nonce.(j) ] else [])
             @ if pos.((2 * j) + 1) = 2 then [ t.(j).(bind.(j)) ] else []))
    in
    let kkey pos bind =
      String.init (2 * m) (fun c ->
          let j = c / 2 in
          if c mod 2 = 0 then if pos.(2 * j) >= 1 then '1' else '0'
          else if pos.((2 * j) + 1) = 2 then Char.chr (Char.code 'a' + bind.(j))
          else '-')
    in
    let dcache : (string * int, bool) Hashtbl.t = Hashtbl.create 1024 in
    (* target id: l < m is nonce N_l; m + j is t_j(N_j) *)
    let der pos bind tid =
      let key = (kkey pos bind, tid) in
      match Hashtbl.find_opt dcache key with
      | Some b -> b
      | None ->
          let target = if tid < m then nonce.(tid) else t.(tid - m).(tid - m) in
          let b = Dy.derivable (k0 @ sent pos bind) target in
          Hashtbl.add dcache key b;
          b
    in
    let violated pos bind =
      let rec go j =
        j < m
        && ((pos.(2 * j) = 2 && not (pos.((2 * j) + 1) = 2 && bind.(j) = j)) || go (j + 1))
      in
      go 0
    in
    let state_key pos bind =
      String.init (3 * m) (fun c ->
          if c < 2 * m then Char.chr (Char.code '0' + pos.(c))
          else Char.chr (Char.code 'a' + 1 + bind.(c - (2 * m))))
    in
    (* the generators outside the trust whose key, removed from k0, breaks a reception
       of the run (trace in execution order) *)
    let stops_of trace =
      List.fold_left
        (fun acc i ->
          let a = Synth.atom i in
          if Aset.mem a trust then acc
          else
            let k = name (Printf.sprintf "k_%02d" i) in
            let rec replay known = function
              | [] -> false
              | Send msg :: rest -> replay (msg :: known) rest
              | Recv msg :: rest -> (not (Dy.derivable known msg)) || replay known rest
            in
            if replay (List.filter (fun x -> not (Term.equal x k)) k0) trace then
              Aset.add a acc
            else acc)
        Aset.empty (List.init n Fun.id)
    in
    let seen = Hashtbl.create 4096 in
    let stack = Stack.create () in
    Stack.push (Array.make (2 * m) 0, Array.make m (-1), []) stack;
    let result = ref None in
    while !result = None && not (Stack.is_empty stack) do
      let pos, bind, rtrace = Stack.pop stack in
      let sk = state_key pos bind in
      if not (Hashtbl.mem seen sk) then begin
        Hashtbl.add seen sk ();
        if violated pos bind then result := Some (List.rev rtrace)
        else
          for sid = 0 to (2 * m) - 1 do
            let j = sid / 2 in
            if pos.(sid) < 2 then begin
              let npos = Array.copy pos in
              npos.(sid) <- pos.(sid) + 1;
              match (sid mod 2, pos.(sid)) with
              | 0, 0 -> Stack.push (npos, bind, Send nonce.(j) :: rtrace) stack
              | 0, _ ->
                  if der pos bind (m + j) then
                    Stack.push (npos, bind, Recv t.(j).(j) :: rtrace) stack
              | _, 0 ->
                  for l = 0 to m - 1 do
                    if der pos bind l then begin
                      let nbind = Array.copy bind in
                      nbind.(j) <- l;
                      Stack.push (npos, nbind, Recv nonce.(l) :: rtrace) stack
                    end
                  done
              | _, _ -> Stack.push (npos, bind, Send t.(j).(bind.(j)) :: rtrace) stack
            end
          done
      end
    done;
    match !result with
    | None -> Loop.Achieves
    | Some trace ->
        Loop.Fails
          {
            stops = stops_of trace;
            descr = Printf.sprintf "violating run of %d events" (List.length trace);
          }

type check = {
  trusts : int;
  agree : int;
  loop_w_equal : bool;
  loop_h_equal : bool;
  gadget_distinct : int;
  time : float;
}

let check ~n h =
  let t0 = Unix.gettimeofday () in
  let g = oracle ~n h in
  let u = Synth.universe n in
  let atoms = Array.of_list (Aset.elements u) in
  let agree = ref 0 in
  for mask = 0 to (1 lsl n) - 1 do
    let trust = ref Aset.empty in
    Array.iteri (fun i a -> if mask land (1 lsl i) <> 0 then trust := Aset.add a !trust) atoms;
    let ok =
      match (g !trust, Synth.hypergraph_oracle h !trust) with
      | Loop.Achieves, Loop.Achieves -> true
      | Loop.Fails w, Loop.Fails _ ->
          List.exists (Aset.equal w.stops) h && Aset.disjoint w.stops !trust
      | _ -> false
    in
    if ok then incr agree
  done;
  let w, h', st = Loop.weakest ~u g in
  {
    trusts = 1 lsl n;
    agree = !agree;
    loop_w_equal = Clutter.equal_family w (Clutter.blocker h);
    loop_h_equal = Clutter.equal_family h' h;
    gadget_distinct = st.distinct;
    time = Unix.gettimeofday () -. t0;
  }
