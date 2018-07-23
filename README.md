# Qubes Mirage ssh-agent

A WIP ssh-agent [Mirage](https://mirage.io/) unikernel for [Qubes OS](https://qubes-os.org/).

## How to build

First, you need to install `opam` the OCaml package manager. Check out the instructions at http://opam.ocaml.org/doc/Install.html.
Once installed it will use the system-installed OCaml compiler.
You may have to compile a newer version of OCaml - for example version 4.02.3 is confirmed not to work (the version shipped with debian 9). Version 4.05.0 is confirmed to work.
To compile 4.05.0, run `opam switch install 4.05.0`. Then run `eval $(opam config env)` as the command should tell you to do.

You should now have a working OCaml setup to continue.

The following two dependencies must be pinned.
The angstrom repository has to be pinned until https://github.com/inhabitedtype/angstrom/issues/118 is fixed.

    opam pin add --no-action -y ssh-agent https://github.com/reynir/ocaml-ssh-agent.git
    opam install -y mirage

To compile:

    mirage configure -t xen
    make depends
    make

There are external dependencies that you may have to install separately, e.g. perhaps curl. Please open an issue if you discover any missing steps.

See [qubes-app-split-ssh](https://github.com/henn/qubes-app-split-ssh) on how you can set up client VMs to use the ssh-agent.
