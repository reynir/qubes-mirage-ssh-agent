open Mirage

let main =
  let packages = [
    package ~build:true ~min:"4.08.0" "ocaml";
    package "mirage-qubes";
    package "ssh-agent";
    package "angstrom";
  ] in
  foreign ~packages ~deps:[abstract nocrypto]
    "Unikernel.Main" (pclock @-> qubesdb @-> job)

let () =
  register "qubes-ssh-agent" ~argv:no_argv [ main $ default_posix_clock $ default_qubesdb ]
