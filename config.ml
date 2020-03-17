open Mirage

let main =
  let packages = [
    package "mirage-qubes";
    package "ssh-agent";
    package "angstrom";
  ] in
  foreign ~packages ~deps:[abstract nocrypto]
    "Unikernel.Main" (pclock @-> qubesdb @-> job)

let () =
  register "qubes-ssh-agent" ~argv:no_argv [ main $ default_posix_clock $ default_qubesdb ]
