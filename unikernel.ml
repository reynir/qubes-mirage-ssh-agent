open Lwt.Infix

let src = Logs.Src.create "unikernel" ~doc:"Main unikernel code"
module Log = (val Logs.src_log src : Logs.LOG)

let prefix = "QUBESRPC qubes.SshAgent "

let with_faraday (f : Faraday.t -> unit) : string =
  let buf = Faraday.create 1024 in
  f buf;
  Faraday.serialize_to_string buf

let rec handler ~user command flow : int Lwt.t =
  Log.info (fun f -> f "Connection %S:%S\n" user command);
  let prefix' = String.sub command 0 (String.length prefix) in
  if prefix <> prefix'
  then begin Log.info (fun f -> f "Wrong prefix");
    Lwt.return 0 (* Ignore, I guess *) end
  else Qubes.RExec.Flow.read flow >>= function
    | `Eof ->
      Log.info (fun f -> f "EOF");
      Lwt.return 0
    | `Ok raw_request ->
      Log.info (fun f -> f "Got a request of len %d" (String.length (Cstruct.to_string raw_request)));
      match Angstrom.parse_string
              Ssh_agent.Parse.ssh_agentc_message
              (Cstruct.to_string raw_request) with
      | Error e ->
        Log.err (fun f -> f "Error parsing request %s" e);
        Lwt.return 1
      | Ok (Ssh_agent.Any_request req) ->
        Log.info (fun f -> f "Succesfully parsed");
        let resp = Agent.handler req in
        Log.info (fun f -> f "Writing response...");
        let resp =
          with_faraday (fun t ->
              Ssh_agent.Serialize.write_ssh_agent_response t resp) in
        Qubes.RExec.Flow.write flow (Cstruct.of_string resp) >>= fun () ->
        handler ~user command flow

module Main (DB : Qubes.S.DB) = struct

  let start qubesdb () =
    Log.info (fun f -> f "Starting...");
    let qrexec = Qubes.RExec.connect ~domid:0 () in
    let gui = Qubes.GUI.connect ~domid:0 () in
    qrexec >>= fun qrexec ->
    let agent_listener = Qubes.RExec.listen qrexec
        handler in
    gui >>= fun gui ->
    Lwt.async (fun () -> Qubes.GUI.listen gui);
    Lwt.async (fun () -> OS.Lifecycle.await_shutdown_request () >>=
                fun (`Poweroff | `Reboot) -> Qubes.RExec.disconnect qrexec);
    Log.info (fun f -> f "Ready to listen");
    Memory_pressure.init ();
    agent_listener

end
