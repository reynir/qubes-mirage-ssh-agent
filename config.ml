open Mirage

let main =
  let packages = [
    package ~build:true ~min:"3.7.5" "mirage";
    package "mirage-qubes";
    package "mirage-xen";
    package ~min:"0.4.0" "ssh-agent";
    package "angstrom";
    package "mirage-crypto-pk";
  ] in
  foreign ~packages
    "Unikernel.Main" (random @-> qubesdb @-> job)

let () =
  register "qubes-ssh-agent" ~argv:no_argv [ main $ default_random $ default_qubesdb ]
