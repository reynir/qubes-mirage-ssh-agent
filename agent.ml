open Lwt.Infix

let src = Logs.Src.create "ssh-agent" ~doc:"Ssh-agent logic"
module Log = (val Logs.src_log src : Logs.LOG)

type identity = { privkey : Ssh_agent.Privkey.t; comment : string }

let pubkey_identity_of_identity { privkey; comment } =
  match privkey with
  | Ssh_agent.Privkey.Ssh_rsa key ->
    { Ssh_agent.pubkey = Ssh_agent.Pubkey.Ssh_rsa (Nocrypto.Rsa.pub_of_priv key);
      comment }
  | Ssh_agent.Privkey.Ssh_rsa_cert (_key, cert) ->
    { Ssh_agent.pubkey = Ssh_agent.Pubkey.Ssh_rsa_cert cert;
      comment }
  | Ssh_agent.Privkey.Ssh_dss key ->
    { Ssh_agent.pubkey = Ssh_agent.Pubkey.Ssh_dss (Nocrypto.Dsa.pub_of_priv key); comment }
  | Ssh_agent.Privkey.Blob _ ->
    failwith "Can't handle this key type"

let identities : identity list ref = ref []

let handler ~confirmation ~vm (type req_type) (request : req_type Ssh_agent.ssh_agent_request)
  : (req_type Ssh_agent.ssh_agent_response) Lwt.t =
  let open Ssh_agent in
  match request with
  | Ssh_agentc_request_identities ->
    let identities = List.map pubkey_identity_of_identity !identities in
    Lwt.return @@ Ssh_agent_identities_answer identities
  | Ssh_agentc_sign_request (pubkey,blob,flags) ->
    begin match List.find (fun id ->
        (pubkey_identity_of_identity id).pubkey = pubkey)
        !identities with
    | { privkey; comment } ->
      let msg = Printf.sprintf "Can vm %s use key %s ?" vm comment in
      let promise, resolver = Lwt.wait () in
      confirmation ~msg
        (function
          | true ->
            Log.info (fun f -> f "Signing using key %s\n%!" comment);
            let signature = Ssh_agent.sign privkey flags blob in
            Lwt.wakeup resolver (Ssh_agent_sign_response signature);
            Lwt.return_unit
          | false ->
            Log.info (fun f -> f "Refused vm %s usage of key %s" vm comment);
            Lwt.wakeup resolver Ssh_agent_failure;
            Lwt.return_unit) >>= begin function
        | `Closed ->
          Lwt.return Ssh_agent_failure
        | `Ok ->
          promise
      end
    | exception Not_found ->
      Lwt.return @@ Ssh_agent_failure
    end
  | Ssh_agentc_add_identity { privkey; key_comment } ->
    identities := { privkey; comment = key_comment } :: !identities;
    Lwt.return @@ Ssh_agent_success
  | Ssh_agentc_remove_identity _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_remove_all_identities ->
    identities := [];
    Lwt.return @@ Ssh_agent_success
  | Ssh_agentc_add_smartcard_key _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_remove_smartcard_key _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_lock _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_unlock _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_add_id_constrained _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_add_smartcard_key_constrained _ ->
    Lwt.return @@ Ssh_agent_failure
  | Ssh_agentc_extension _ ->
    Lwt.return @@ Ssh_agent_failure

