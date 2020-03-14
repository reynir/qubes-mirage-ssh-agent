open Mirage

let main =
  let packages = [
    package "mirage-qubes";
    package "ssh-agent";
    package "angstrom";
  ] in
  foreign ~packages
    "Unikernel.Main" (qubesdb @-> job)

let () =
  register "qubes-ssh-agent" ~argv:no_argv [ main $ default_qubesdb ]
