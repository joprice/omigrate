(* open Omigrate *)

let run ?admin_db ~database () = Omigrate.drop ?admin_db ~database () |> Lwt_main.run

(* Command line interface *)

open Cmdliner

let doc = "Delete the database."
let sdocs = Manpage.s_common_options
let exits = Common.exits
let envs = Common.envs

let man =
  [ `S Manpage.s_description; `P "$(tname) deletes the database if it exists." ]

let info = Cmd.info "drop" ~doc ~sdocs ~exits ~envs ~man

let term =
  let open Common.Let_syntax in
  let+ _term = Common.term 
  and+ database = Common.database_arg 
  and+ admin_db = Common.admin_db_arg
  in
  run ?admin_db ~database () |> Common.handle_errors

let cmd = Cmd.v info term
