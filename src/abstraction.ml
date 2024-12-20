open Common

let is_unique_fresh (var : Formula.var) (formula : Formula.t) : bool =
  is_fresh_var var && Formula.count_occurences_excl_distinct var formula = 2

let is_in_formula (src : Formula.var) (dst : Formula.var)
    (field : Preprocessing.field_type) (formula : Formula.t) : bool =
  Formula.get_spatial_atom_from_opt src formula
  |> Option.map (fun atom ->
         Formula.get_target_of_atom field atom |> fun atom_dst ->
         Formula.is_eq atom_dst dst formula)
  |> Option.value ~default:false

let convert_to_ls (formula : Formula.t) : Formula.t =
  let atom_to_ls : Formula.atom -> Formula.ls option = function
    | Formula.LS ls -> Some ls
    | Formula.PointsTo (first, LS_t next) -> Some { first; next; min_len = 1 }
    | _ -> None
  in

  let do_abstraction (formula : Formula.t) (first_ls : Formula.ls) : Formula.t =
    match
      formula
      |> Formula.get_spatial_atom_from_opt first_ls.next
      |> Option.map atom_to_ls |> Option.join
    with
    | Some second_ls
    (* conditions for abstraction *)
      when (* first_ls must still be in formula *)
           is_in_formula first_ls.first first_ls.next Preprocessing.Next formula
           (* middle must be fresh variable, and occur only in these two predicates *)
           && is_unique_fresh first_ls.next formula
           (* src must be different from dst (checked using solver) *)
           && Astral_query.check_inequality first_ls.first second_ls.next
                formula ->
        let min_length = min 2 (first_ls.min_len + second_ls.min_len) in
        formula
        |> Formula.remove_spatial_from first_ls.first
        |> Formula.remove_spatial_from second_ls.first
        |> Formula.add_atom
           @@ Formula.mk_ls first_ls.first second_ls.next min_length
    | _ -> formula
  in

  formula |> List.filter_map atom_to_ls |> List.fold_left do_abstraction formula

let convert_to_dls (formula : Formula.t) : Formula.t =
  let atom_to_dls : Formula.atom -> Formula.dls option = function
    | Formula.DLS dls -> Some dls
    | Formula.PointsTo (src, DLS_t (next, prev)) ->
        Some { first = src; last = src; next; prev; min_len = 1 }
    | _ -> None
  in

  (* unlike ls and nls, dls contains each variable 3 times *)
  let is_unique_fresh (var : Formula.var) (formula : Formula.t) : bool =
    is_fresh_var var && Formula.count_occurences_excl_distinct var formula = 3
  in

  let do_abstraction (formula : Formula.t) (first_dls : Formula.dls) : Formula.t
      =
    let second_dls =
      formula
      |> Formula.get_spatial_atom_from_opt first_dls.next
      |> Option.map atom_to_dls |> Option.join
    in

    let third_dls =
      Option.map
        (fun (second_dls : Formula.dls) ->
          formula
          |> Formula.get_spatial_atom_from_opt second_dls.next
          |> Option.map atom_to_dls)
        second_dls
      |> Option.join |> Option.join
    in

    match (second_dls, third_dls) with
    | Some second_dls, Some third_dls
    (* conditions for abstraction *)
      when (* first_dls must still be in formula *)
           is_in_formula first_dls.first first_dls.next Preprocessing.Next
             formula
           (* middle vars must be fresh, and occur only in these two predicates *)
           && is_unique_fresh second_dls.first formula
           && is_unique_fresh second_dls.last formula
           (* `prev` pointers from second and third DLS must lead to end of the previous DLS *)
           && Formula.is_eq first_dls.last second_dls.prev formula
           && Formula.is_eq second_dls.last third_dls.prev formula
           (* DLS must not be cyclic (checked both forward and backward) *)
           && Astral_query.check_inequality first_dls.first third_dls.next
                formula
           && Astral_query.check_inequality third_dls.last first_dls.prev
                formula ->
        let min_length =
          min 3 (first_dls.min_len + second_dls.min_len + second_dls.min_len)
        in
        formula
        |> Formula.remove_spatial_from first_dls.first
        |> Formula.remove_spatial_from second_dls.first
        |> Formula.remove_spatial_from third_dls.first
        |> Formula.add_atom
           @@ Formula.mk_dls first_dls.first third_dls.last first_dls.prev
                third_dls.next min_length
    | _ -> formula
  in

  formula
  |> List.filter_map atom_to_dls
  |> List.fold_left do_abstraction formula

let convert_to_nls (formula : Formula.t) : Formula.t =
  let atom_to_nls : Formula.atom -> Formula.nls option = function
    | Formula.NLS nls -> Some nls
    | Formula.PointsTo (first, NLS_t (top, next)) ->
        Some { first; top; next; min_len = 1 }
    | _ -> None
  in

  let do_abstraction (formula : Formula.t) (first_nls : Formula.nls) : Formula.t
      =
    match
      formula
      |> Formula.get_spatial_atom_from_opt first_nls.top
      |> Option.map atom_to_nls |> Option.join
    with
    | Some second_nls
    (* conditions for abstraction *)
      when (* first_nls must still be in formula *)
           is_in_formula first_nls.first first_nls.top Preprocessing.Top formula
           (* middle must be fresh variable, and occur only in these two predicates *)
           && is_unique_fresh first_nls.top formula
           (* src must be different from dst (checked using solver) *)
           && Astral_query.check_inequality first_nls.first second_nls.top
                (* common variable `next` must lead to the same target *)
                formula
           && Formula.is_eq first_nls.next second_nls.next formula ->
        let min_length = min 2 (first_nls.min_len + second_nls.min_len) in
        formula
        |> Formula.remove_spatial_from first_nls.first
        |> Formula.remove_spatial_from second_nls.first
        |> Formula.add_atom
           @@ Formula.mk_nls first_nls.first second_nls.top first_nls.next
                min_length
    | _ -> formula
  in

  formula
  |> List.filter_map atom_to_nls
  |> List.fold_left do_abstraction formula

module Tests = struct
  open Testing

  let%test "abstraction_ls_nothing" =
    let input = [ PointsTo (x, LS_t y'); PointsTo (y', LS_t z) ] in
    assert_eq (convert_to_ls input) input

  let%test "abstraction_ls_1" =
    let input =
      [ PointsTo (x, LS_t y'); PointsTo (y', LS_t z); Distinct (x, z) ]
    in
    let result = convert_to_ls input in
    let expected = [ mk_ls x z 2; Distinct (x, z) ] in
    assert_eq result expected

  let%test "abstraction_ls_2" =
    let input =
      [
        PointsTo (x, LS_t y');
        PointsTo (y', LS_t z);
        PointsTo (u, LS_t v');
        PointsTo (v', LS_t w);
        Distinct (u, w);
      ]
    in
    let result = convert_to_ls input in
    let expected =
      [
        PointsTo (x, LS_t y');
        PointsTo (y', LS_t z);
        mk_ls u w 2;
        Distinct (u, w);
      ]
    in
    assert_eq result expected

  let%test "abstraction_ls_3" =
    let input =
      [
        PointsTo (x, LS_t y');
        PointsTo (y', LS_t z');
        PointsTo (z', LS_t w);
        Distinct (x, w);
      ]
    in
    let result = convert_to_ls input in
    let expected = [ mk_ls x z' 2; PointsTo (z', LS_t w); Distinct (x, w) ] in
    assert_eq result expected

  let%test "abstraction_ls_double" =
    let input =
      [
        PointsTo (x, LS_t y');
        PointsTo (y', LS_t z');
        PointsTo (z', LS_t w);
        Distinct (x, w);
      ]
    in
    let result = convert_to_ls @@ convert_to_ls input in
    let expected = [ mk_ls x w 2; Distinct (x, w) ] in
    assert_eq result expected

  let%test "abstraction_dls_nothing" =
    let input =
      [
        PointsTo (u, DLS_t (v', z));
        PointsTo (v', DLS_t (w, u));
        PointsTo (w, DLS_t (x, v'));
        Distinct (u, x);
      ]
    in
    assert_eq (convert_to_dls input) input

  let%test "abstraction_dls_1" =
    let input =
      [
        PointsTo (u, DLS_t (v', z));
        PointsTo (v', DLS_t (w, u));
        PointsTo (w, DLS_t (x, v'));
        Distinct (u, x);
        Distinct (w, z);
      ]
    in
    let expected = [ mk_dls u w z x 3; Distinct (u, x); Distinct (w, z) ] in
    assert_eq (convert_to_dls input) expected

  let%test "abstraction_dls_2" =
    let input =
      [
        PointsTo (u, DLS_t (v', z));
        PointsTo (v', DLS_t (w, u));
        PointsTo (w, DLS_t (x, v'));
        PointsTo (x, DLS_t (y, w'));
        Distinct (w, z);
      ]
    in
    let expected =
      [ mk_dls u w z x 3; PointsTo (x, DLS_t (y, w')); Distinct (w, z) ]
    in
    assert_eq (convert_to_dls input) expected

  let%test "abstraction_dls_long_nothing" =
    let input =
      [
        PointsTo (u, DLS_t (v, z));
        PointsTo (v, DLS_t (w, u));
        PointsTo (w, DLS_t (x, v));
        PointsTo (x, DLS_t (y, w));
        PointsTo (y, DLS_t (z, x));
      ]
    in
    assert_eq (convert_to_dls input) input

  let%test "abstraction_dls_long_1" =
    let input =
      [
        PointsTo (u, DLS_t (v, z));
        PointsTo (v, DLS_t (w', u));
        PointsTo (w', DLS_t (x, v));
        PointsTo (x, DLS_t (y, w'));
        PointsTo (y, DLS_t (z, x));
      ]
    in
    let expected =
      [
        PointsTo (u, DLS_t (v, z)); mk_dls v x u y 3; PointsTo (y, DLS_t (z, x));
      ]
    in
    assert_eq (convert_to_dls input) expected
end
