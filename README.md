# Qubes Mirage ssh-agent

A WIP ssh-agent [Mirage](https://mirage.io/) unikernel for [Qubes OS](https://qubes-os.org/).

## How to build

The following two dependencies must be pinned.
The angstrom repository has to be pinned until https://github.com/inhabitedtype/angstrom/issues/118 is fixed.

    opam pin add angstrom https://github.com/reynir/angstrom.git#no-c-blit
    opam pin add ssh-agent https://github.com/reynir/ocaml-ssh-agent.git
    opam install mirage

To compile:

    mirage configure -t xen
    make depends
    make


