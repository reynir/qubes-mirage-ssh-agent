open Mirage

let main =
  let packages = [
    package ~min:"3.7.5" "mirage";
    package "mirage-qubes";
    package "ssh-agent";
    package "angstrom";
    package "mirage-crypto-pk";
  ] in
  foreign ~packages
    "Unikernel.Main" (qubesdb @-> job)

let () =
  register "qubes-ssh-agent" ~argv:no_argv [ main $ default_qubesdb ]
