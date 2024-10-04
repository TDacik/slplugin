let format_stmt (fmt : Format.formatter) (loc : Printer_tag.localizable) : unit
    =
  let sid =
    match loc with Printer_tag.PStmtStart (_, stmt) -> stmt.sid | _ -> -111111
  in
  (* let result = *)
  (*   match loc with *)
  (*   | Printer_tag.PStmtStart (_, stmt) -> *)
  (*       Option.to_list @@ Hashtbl.find_opt !Common.results stmt |> List.flatten *)
  (*   | _ -> [] *)
  (* in *)
  (* let result_string = *)
  (*   match result with *)
  (*   | [] -> "<no data>" *)
  (*   | data -> List.map Astral.SSL.show data |> String.concat "\n" *)
  (* in *)
  ignore @@ Format.pp_print_string fmt (string_of_int sid)

let () =
  Server.Kernel_ast.Information.register ~id:"slplugin.stmt_state"
    ~label:"state" ~title:"final state"
    ~descr:"final state reached for this statement" format_stmt
