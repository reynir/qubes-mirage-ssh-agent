let src = Logs.Src.create "ssh-agent" ~doc:"Ssh-agent logic"
module Log = (val Logs.src_log src : Logs.LOG)

type identity = {
  privkey : Ssh_agent.Privkey.t;
  comment : string;
  confirmation : bool;
  end_of_lifetime : Ptime.t option;
}

let pubkey_identity_of_identity { privkey; comment; _ } =
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

let handler (type req_type) now (request : req_type Ssh_agent.ssh_agent_request)
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
    | { end_of_lifetime = Some end_of_lifetime; _ } when Ptime.is_later end_of_lifetime ~than:now ->
      Ssh_agent_failure
    | { privkey; comment; confirmation = false; end_of_lifetime = _ } ->
      Log.info (fun f -> f "Signing using key %s\n%!" comment);
          let signature = Ssh_agent.sign privkey flags blob in
          Ssh_agent_sign_response signature
    | { confirmation = true; _ } ->
      Log.warn (fun f -> f "Confirmation dialog not yet implemented");
      Ssh_agent_failure
    | exception Not_found ->
      Ssh_agent_failure
    end
  | Ssh_agentc_add_identity { privkey; key_comment } ->
    let new_identities =
      List.filter (fun { privkey = other_privkey; _ } -> other_privkey <> privkey) !identities in
    identities := { privkey; comment = key_comment;
                    confirmation = false; end_of_lifetime = None }
                  :: new_identities;
    Ssh_agent_success
  | Ssh_agentc_remove_identity pubkey ->
    let new_identities =
      List.filter (fun identity ->
          let pub_identity = pubkey_identity_of_identity identity in
          pub_identity.pubkey <> pubkey)
        !identities
    in identities := new_identities;
    Ssh_agent_success
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
  | Ssh_agentc_add_id_constrained { privkey; key_comment; key_constraints = [Confirm] } ->
    let new_identities =
      List.filter (fun { privkey = other_privkey; _ } -> other_privkey <> privkey) !identities in
    identities := { privkey; comment = key_comment;
                    confirmation = true; end_of_lifetime = None }
                  :: new_identities;
    Ssh_agent_success
  | Ssh_agentc_add_id_constrained { privkey; key_comment; key_constraints = [Lifetime lifetime] } ->
    let lifetime = match Int32.unsigned_to_int lifetime with
      | Some lifetime -> lifetime
      | None -> failwith "int should be able to represent uint32" in
    begin match Ptime.add_span now (Ptime.Span.of_int_s lifetime) with
      | None -> Ssh_agent_failure
      | Some end_of_lifetime ->
        let new_identities =
          List.filter (fun { privkey = other_privkey; _ } -> other_privkey <> privkey) !identities in
        identities := { privkey; comment = key_comment;
                        confirmation = false; end_of_lifetime = Some end_of_lifetime }
                      :: new_identities;
        Ssh_agent_success
    end
  | Ssh_agentc_add_id_constrained { privkey; key_comment;
                                    key_constraints = [Lifetime lifetime; Confirm] |
                                                      [Confirm; Lifetime lifetime] } ->
    let lifetime = match Int32.unsigned_to_int lifetime with
      | Some lifetime -> lifetime
      | None -> failwith "int should be able to represent uint32" in
    begin match Ptime.add_span now (Ptime.Span.of_int_s lifetime) with
      | None -> Ssh_agent_failure
      | Some end_of_lifetime ->
        let new_identities =
          List.filter (fun { privkey = other_privkey; _ } -> other_privkey <> privkey) !identities in
        identities := { privkey; comment = key_comment;
                        confirmation = true; end_of_lifetime = Some end_of_lifetime }
                      :: new_identities;
        Ssh_agent_success
    end
  | Ssh_agentc_add_id_constrained { key_constraints = _; _ } ->
    Ssh_agent_failure
  | Ssh_agentc_add_smartcard_key_constrained _ ->
    Ssh_agent_failure
  | Ssh_agentc_extension _ ->
    Ssh_agent_failure

