(* mirage >= 4.9.0 & < 4.12.0 *)
open Mirage

let main =
  main
    ~packages:
    [
      package "mirage-qubes" ~min:"2.0.1";
      package "mirage-xen" ~min:"9.0.1";
      package ~min:"0.4.0" "ssh-agent";
      package "angstrom";
      package "mirage-crypto-pk";
    ]
  "Unikernel.Main" (qubesdb @-> job)

let () =
  register "qubes-ssh-agent" [ main $ default_qubesdb ]
