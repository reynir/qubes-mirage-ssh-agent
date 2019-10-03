open Lwt.Infix

let src = Logs.Src.create "unikernel" ~doc:"Main unikernel code"
module Log = (val Logs.src_log src : Logs.LOG)

let prefix = "QUBESRPC qubes.SshAgent "
let confirmation_vm = "dev"

let with_faraday (f : Faraday.t -> unit) : string =
  let buf = Faraday.create 1024 in
  f buf;
  Faraday.serialize_to_string buf

let bigstring_of_unconsumed { Angstrom.Buffered.buf; len; off } =
  Bigarray.Array1.sub buf off len

let handler (confirmation : msg:string -> (bool -> 'a Lwt.t) -> _ Lwt.t) ~user command flow : int Lwt.t =
  Log.info (fun f -> f "Connection %S:%S\n" user command);
  let prefix' = String.sub command 0 (String.length prefix) in
  if prefix <> prefix'
  then begin Log.info (fun f -> f "Wrong prefix");
    Lwt.return 0 (* Ignore, I guess *) end
  else
    let vm = String.sub command (String.length prefix)
        (String.length command - String.length prefix) in
    let rec loop (state : Ssh_agent.any_ssh_agent_request Angstrom.Buffered.state) =
      match state with
      | Angstrom.Buffered.Done (u, Ssh_agent.Any_request req) ->
        Agent.handler ~confirmation ~vm req >>= fun resp ->
        let resp = with_faraday (fun t ->
            Ssh_agent.Serialize.write_ssh_agent_response t resp) in
        Qubes.RExec.Flow.write flow (Cstruct.of_string resp) >>= fun () ->
        let state = Angstrom.Buffered.parse Ssh_agent.Parse.ssh_agentc_message in
        let state = Angstrom.Buffered.feed state
            (`Bigstring (bigstring_of_unconsumed u)) in
        loop state
      | Angstrom.Buffered.Partial _ ->
        Qubes.RExec.Flow.read flow >>= begin function
          | `Eof ->
            let state = Angstrom.Buffered.feed state `Eof in
            loop state
          | `Ok input ->
            let state = Angstrom.Buffered.feed state (`Bigstring (Cstruct.to_bigarray input)) in
            loop state
        end
      | Angstrom.Buffered.Fail (_, _, e) ->
        Log.debug (fun f -> f "Error parsing request: %s" e);
        Lwt.return 1
    in
    let state = Angstrom.Buffered.parse Ssh_agent.Parse.ssh_agentc_message in
    Qubes.RExec.Flow.read flow >>= function
    | `Ok input ->
      let state = Angstrom.Buffered.feed state (`Bigstring (Cstruct.to_bigarray input)) in
      loop state
    | `Eof ->
      (* Silently ignore quiet clients *)
      Lwt.return 0

module Main (DB : Qubes.S.DB) = struct

  (* We don't use the GUI, but it's interesting to keep an eye on it.
     If the other end dies, don't let it take us with it (can happen on log out). *)
  let watch_gui gui =
    Lwt.async (fun () ->
      Lwt.try_bind
        (fun () ->
           gui >>= fun gui ->
           Log.info (fun f -> f "GUI agent connected");
           Qubes.GUI.listen gui ()
        )
        (fun _ -> assert false)
        (fun ex ->
          Log.warn (fun f -> f "GUI thread failed: %s" (Printexc.to_string ex));
          Lwt.return ()
        )
    )

  let confirmation qrexec ~msg k =
    let async_k b =
      Lwt.async (fun () -> k b) in
    Qubes.RExec.qrexec qrexec
      ~vm:confirmation_vm
      ~service:"reynir.ConfirmationDialog"
      (function
        | `Error msg ->
          Log.err (fun f -> f "Error from confirmation dialog vm: %s" msg);
          async_k false;
          Lwt.return_unit
        | `Closed ->
          Log.err (fun f -> f "Dom0 closed control channel while getting confirmation");
          async_k false;
          Lwt.return_unit
        | `Permission_denied ->
          Log.err (fun f -> f "Got permission denied while talking to confirmation dialog vm %s" confirmation_vm);
          async_k false;
          Lwt.return_unit
        |`Ok flow ->
          Log.debug (fun f -> f "Talking to confirmation vm...");
          let module Client_flow = Qubes.RExec.Client_flow in
          let msg =
            Printf.sprintf "%s\n" (Base64.encode_string msg) in
          Client_flow.write flow (Cstruct.of_string msg) >>= function
          | `Eof ->
            Log.err (fun f -> f "Confirmation vm closed connection prematurely");
            async_k false;
            Lwt.return_unit
          | `Ok () ->
            let rec read acc =
              Client_flow.read flow >>= function
              | `Eof ->
                Lwt.return (Error "closed connection prematurely")
              | `Exit_code exit_code ->
                Lwt.return (Ok (exit_code, acc))
              |`Stdout cs ->
                read (Cstruct.append acc cs)
              |`Stderr cs ->
                Log.debug (fun f -> f "Confirmation vm wrote to stderr: %s"
                              (Cstruct.to_string cs));
                read acc
            in
            read Cstruct.empty >>= function
            | Error msg ->
              Log.err (fun f -> f "Confirmation vm %s" msg);
              async_k false;
              Lwt.return_unit
            | Ok (0l, cs) ->
              begin match Cstruct.to_string cs with
              | "true" | "true\n" ->
                async_k true;
                Lwt.return_unit
              | "false" | "false\n" ->
                async_k false;
                Lwt.return_unit
              | garbage ->
                Log.err (fun f -> f "Confirmation vm responded with garbage: %S" garbage);
                Lwt.return_unit
              end
            | Ok (exit_code, cs) ->
              Log.err (fun f -> f "Confirmation vm call exited with non-zero exit code %lu" exit_code);
              Log.debug (fun f -> f "Confirmation vm wrote to stdout: %S" (Cstruct.to_string cs));
              Lwt.return_unit)


  let start qubesdb () =
    Log.info (fun f -> f "Starting...");
    let qrexec = Qubes.RExec.connect ~domid:0 () in
    Qubes.GUI.connect ~domid:0 () |> watch_gui;
    qrexec >>= fun qrexec ->
    let agent_listener = Qubes.RExec.listen qrexec
        (handler (confirmation qrexec)) in
    Lwt.async (fun () -> OS.Lifecycle.await_shutdown_request () >>=
                fun (`Poweroff | `Reboot) -> Qubes.RExec.disconnect qrexec);
    Log.info (fun f -> f "Ready to listen");
    agent_listener

end
