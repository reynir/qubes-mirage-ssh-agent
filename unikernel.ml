open Lwt.Infix

let src = Logs.Src.create "unikernel" ~doc:"Main unikernel code"
module Log = (val Logs.src_log src : Logs.LOG)

let prefix = "QUBESRPC qubes.SshAgent "

let with_faraday (f : Faraday.t -> unit) : string =
  let buf = Faraday.create 1024 in
  f buf;
  Faraday.serialize_to_string buf

let bigstring_of_unconsumed { Angstrom.Buffered.buf; len; off } =
  Bigarray.Array1.sub buf off len

let handler ~user command flow : int Lwt.t =
  Log.info (fun f -> f "Connection %S:%S\n" user command);
  let prefix' = String.sub command 0 (String.length prefix) in
  if prefix <> prefix'
  then begin Log.info (fun f -> f "Wrong prefix");
    Lwt.return 0 (* Ignore, I guess *) end
  else
    let rec loop (state : Ssh_agent.any_ssh_agent_request Angstrom.Buffered.state) =
      match state with
      | Angstrom.Buffered.Done (u, Ssh_agent.Any_request req) ->
        let resp = Agent.handler req in
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
    loop (Angstrom.Buffered.parse Ssh_agent.Parse.ssh_agentc_message)

module Main (DB : Qubes.S.DB) = struct

  (* We don't use the GUI, but it's interesting to keep an eye on it.
     If the other end dies, don't let it take us with it (can happen on log out). *)
  let watch_gui gui =
    Lwt.async (fun () ->
      Lwt.try_bind
        (fun () ->
           gui >>= fun gui ->
           Log.info (fun f -> f "GUI agent connected");
           Qubes.GUI.listen gui
        )
        (fun `Cant_happen -> assert false)
        (fun ex ->
          Log.warn (fun f -> f "GUI thread failed: %s" (Printexc.to_string ex));
          Lwt.return ()
        )
    )

  let start qubesdb () =
    Log.info (fun f -> f "Starting...");
    let qrexec = Qubes.RExec.connect ~domid:0 () in
    Qubes.GUI.connect ~domid:0 () |> watch_gui;
    qrexec >>= fun qrexec ->
    let agent_listener = Qubes.RExec.listen qrexec
        handler in
    Lwt.async (fun () -> OS.Lifecycle.await_shutdown_request () >>=
                fun (`Poweroff | `Reboot) -> Qubes.RExec.disconnect qrexec);
    Log.info (fun f -> f "Ready to listen");
    agent_listener

end
