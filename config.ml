open Mirage

let main =
  let packages = [
    package ~build:true ~max:"3.7.5" "mirage";
    package "mirage-qubes";
    package "ssh-agent";
    package "angstrom";
  ] in
  foreign ~packages ~deps:[abstract nocrypto]
    "Unikernel.Main" (qubesdb @-> job)

let () =
  register "qubes-ssh-agent" ~argv:no_argv [ main $ default_qubesdb ]
