let src = Logs.Src.create "ssh-agent" ~doc:"Ssh-agent logic"
module Log = (val Logs.src_log src : Logs.LOG)

type identity = { privkey : Ssh_agent.Privkey.t; comment : string }

let pubkey_identity_of_identity { privkey; comment } =
  match privkey with
  | Ssh_agent.Privkey.Ssh_rsa key ->
    { Ssh_agent.pubkey = Ssh_agent.Pubkey.Ssh_rsa (Mirage_crypto_pk.Rsa.pub_of_priv key);
      comment }
  | Ssh_agent.Privkey.Ssh_rsa_cert (_key, cert) ->
    { Ssh_agent.pubkey = Ssh_agent.Pubkey.Ssh_rsa_cert cert;
      comment }
  | Ssh_agent.Privkey.Ssh_dss key ->
    { Ssh_agent.pubkey = Ssh_agent.Pubkey.Ssh_dss (Mirage_crypto_pk.Dsa.pub_of_priv key); comment }
  | Ssh_agent.Privkey.Blob _ ->
    failwith "Can't handle this key type"

let identities : identity list ref = ref []

let handler (type req_type) (request : req_type Ssh_agent.ssh_agent_request)
  : req_type Ssh_agent.ssh_agent_response =
  let open Ssh_agent in
  match request with
  | Ssh_agentc_request_identities ->
    let identities = List.map pubkey_identity_of_identity !identities in
    Ssh_agent_identities_answer identities
  | Ssh_agentc_sign_request (pubkey,blob,flags) ->
    begin match List.find (fun id ->
        (pubkey_identity_of_identity id).pubkey = pubkey)
        !identities with
    | { privkey; comment } ->
      Log.info (fun f -> f "Signing using key %s\n%!" comment);
      let signature = Ssh_agent.sign privkey flags blob in
      Ssh_agent_sign_response signature
    | exception Not_found ->
      Ssh_agent_failure
    end
  | Ssh_agentc_add_identity { privkey; key_comment } ->
    identities := { privkey; comment = key_comment } :: !identities;
    Ssh_agent_success
  | Ssh_agentc_remove_identity _ ->
    Ssh_agent_failure
  | Ssh_agentc_remove_all_identities ->
    identities := [];
    Ssh_agent_success
  | Ssh_agentc_add_smartcard_key _ ->
    Ssh_agent_failure
  | Ssh_agentc_remove_smartcard_key _ ->
    Ssh_agent_failure
  | Ssh_agentc_lock _ ->
    Ssh_agent_failure
  | Ssh_agentc_unlock _ ->
    Ssh_agent_failure
  | Ssh_agentc_add_id_constrained _ ->
    Ssh_agent_failure
  | Ssh_agentc_add_smartcard_key_constrained _ ->
    Ssh_agent_failure
  | Ssh_agentc_extension _ ->
    Ssh_agent_failure

