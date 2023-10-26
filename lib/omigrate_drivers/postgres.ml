open Caqti_request.Infix
open Caqti_type.Std

module T = struct
  let default_user = "postgres"
  let default_password = "postgres"
  let default_port = 5432
  let migrations_table = "schema_migrations"
  let quote_statement s = "\"" ^ s ^ "\""

  let recover result =
    result
    |> Lwt_result.map_error (fun e -> Failure (Caqti_error.show e))
    |> Lwt_result.get_exn

  let ensure_version_table_exists ~db:(module Db : Caqti_lwt.CONNECTION) =
    let open Lwt.Syntax in
    let* () =
      Logs_lwt.info (fun m -> m "Creating the migrations table if not exists")
    in
    let query =
      (unit ->. unit)
      @@ "CREATE TABLE IF NOT EXISTS "
      ^ quote_statement migrations_table
      ^ "(version bigint NOT NULL, dirty boolean NOT NULL, CONSTRAINT \
         schema_migrations_pkey PRIMARY KEY (version));"
    in
    Db.exec query () |> recover

  let with_conn ~host ?(port = default_port) ?(user = default_user)
      ?(password = default_password) ?database f =
    let open Lwt.Syntax in
    let* () =
      Logs_lwt.debug (fun m ->
          m "Opening a conection on postgres://%s:%s@%s:%d/%a" user password
            host port
            (Format.pp_print_option Format.pp_print_string)
            database)
    in
    let uri =
      Uri.make ~scheme:"postgresql" ~host ~port
        ~userinfo:(user ^ ":" ^ password)
        ?path:(database |> Option.map (fun database -> "/" ^ database))
        ()
    in
    Caqti_lwt_unix.with_connection uri f

  let with_transaction ~host ?(port = default_port) ?user ?password ?database f
      =
    with_conn ~host ~port ?user ?password ?database
      (fun ((module Db : Caqti_lwt.CONNECTION) as conn) ->
        Db.with_transaction (fun () -> f conn))

  let database_exists ~conn:(module Db : Caqti_lwt.CONNECTION) database =
    recover
    @@
    let open Lwt.Syntax in
    let* () = Logs_lwt.debug (fun m -> m "Querying existing databases") in
    let query =
      (string ->! bool)
      @@ "SELECT EXISTS(SELECT datname FROM pg_catalog.pg_database WHERE \
          datname = ?);"
    in
    Db.find query database

  let execute (module Db : Caqti_lwt.CONNECTION) query =
    Db.exec ((unit ->. unit) @@ query) () |> recover

  let split_statements migration =
    String.split_on_char ';' migration
    |> List.map String.trim
    |> List.filter (fun line -> String.length line > 0)

  let run_statements db migration =
    let statements = split_statements migration in
    statements |> Lwt_list.iter_s (execute db)

  let up ~host ?(port = default_port) ?user ?password ~database migration =
    let open Lwt.Syntax in
    with_transaction ~host ~port ?user ?password ~database
      (fun ((module Db : Caqti_lwt.CONNECTION) as db) ->
        let version = migration.Omigrate.Migration.version in
        let* () =
          Logs_lwt.info (fun m -> m "Applying up migration %Ld" version)
        in
        let* () = run_statements db migration.Omigrate.Migration.up in
        let* () =
          Logs_lwt.debug (fun m ->
              m "Inserting version %Ld in migration table" version)
        in
        let* () =
          execute db ("TRUNCATE " ^ quote_statement migrations_table ^ ";")
        in
        Db.exec
          ((t2 int64 bool ->. unit)
          @@ "INSERT INTO "
          ^ quote_statement migrations_table
          ^ " (version, dirty) VALUES ($1, $2);")
          (version, false))
    |> recover

  let down ~host ?(port = default_port) ?user ?password ~database ?previous
      migration =
    let open Lwt.Syntax in
    recover
    @@ with_transaction ~host ~port ?user ?password ~database
         (fun ((module Db : Caqti_lwt.CONNECTION) as db) ->
           let version = migration.Omigrate.Migration.version in
           let* () =
             Logs_lwt.info (fun m -> m "Applying down migration %Ld" version)
           in
           let* () = run_statements db migration.Omigrate.Migration.down in
           let* () =
             Logs_lwt.debug (fun m ->
                 m "Removing version %Ld from migration table" version)
           in
           let* () =
             execute db ("TRUNCATE " ^ quote_statement migrations_table ^ ";")
           in
           match previous with
           | None -> Lwt.return (Ok ())
           | Some previous ->
               let previous_version = previous.Omigrate.Migration.version in
               Db.exec
                 ((t2 int64 bool ->. unit)
                 @@ "INSERT INTO "
                 ^ quote_statement migrations_table
                 ^ " (version, dirty) VALUES ($1, $2);")
                 (previous_version, false))

  let create ?admin_db ~host ?(port = default_port) ?user ?password database =
    let open Lwt.Syntax in
    let* () =
      recover
      @@ with_conn ~host ~port ?user ?password ?database:admin_db
           (fun ((module Db : Caqti_lwt.CONNECTION) as db) ->
             let* database_exists = database_exists ~conn:db database in
             if database_exists then
               let+ () = Logs_lwt.info (fun m -> m "Database already exists") in
               Ok ()
             else
               let* () = Logs_lwt.info (fun m -> m "Creating the database") in
               let+ () =
                 execute db ("CREATE DATABASE " ^ quote_statement database ^ ";")
               in
               Ok ())
    in
    recover
    @@ with_conn ~host ~port ?user ?password ~database (fun db ->
           let+ () = ensure_version_table_exists ~db in
           Ok ())

  let drop ?admin_db ~host ?(port = default_port) ?user ?password database =
    let open Lwt.Syntax in
    recover
    @@ with_conn ~host ~port ?user ?password ?database:admin_db (fun conn ->
           let* database_exists = database_exists ~conn database in
           if not database_exists then
             let+ () = Logs_lwt.info (fun m -> m "Database does not exists") in
             Ok ()
           else
             let* () = Logs_lwt.info (fun m -> m "Deleting the database") in
             let+ () =
               execute conn ("DROP DATABASE " ^ quote_statement database ^ ";")
             in
             Ok ())

  let version ~host ?(port = default_port) ?user ?password ~database () =
    recover
    @@ with_conn ~host ~port ?user ?password ~database
         (fun (module Db : Caqti_lwt.CONNECTION) ->
           let open Lwt.Syntax in
           let* () = Logs_lwt.debug (fun m -> m "Querying all versions") in
           let query =
             (unit ->? t2 int64 bool)
             @@ "SELECT version, dirty FROM "
             ^ quote_statement migrations_table
             ^ "ORDER BY version DESC LIMIT 1;"
           in
           Db.find_opt query ())

  let parse_uri s =
    let module Omigrate_error = Omigrate.Error in
    let module Connection = Omigrate.Driver.Connection in
    let uri = Uri.of_string s in
    let host = Uri.host_with_default uri in
    let user = Uri.user uri in
    let pass = Uri.password uri in
    let port = Uri.port uri in
    let db_result =
      match Uri.path uri with
      | "/" -> Error (Omigrate_error.bad_uri s)
      | path ->
          if Filename.dirname path <> "/" then Error (Omigrate_error.bad_uri s)
          else Ok (Filename.basename path)
    in
    Result.map (fun db -> Connection.{ host; user; pass; port; db }) db_result
end

let () =
  Omigrate.Driver.register "postgres" (module T);
  Omigrate.Driver.register "postgresql" (module T)
