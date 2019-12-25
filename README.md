# Qubes Mirage ssh-agent

A WIP ssh-agent [Mirage](https://mirage.io/) unikernel for [Qubes OS](https://qubes-os.org/).

## How to build

First, you need to install `opam` the OCaml package manager. Check out the instructions at http://opam.ocaml.org/doc/Install.html.
Once installed it will use the system-installed OCaml compiler.
You may have to compile a newer version of OCaml - for example version 4.02.3 is confirmed not to work (the version shipped with debian 9). Version 4.08.1 is confirmed to work.
To compile 4.08.1, run `opam switch install 4.08.1`. Then run `eval $(opam config env)` as the command should tell you to do.

You should now have a working OCaml setup to continue.

    opam install -y mirage

To compile:

    mirage configure -t xen
    make depends
    make

There are external dependencies that you may have to install separately, e.g. perhaps curl. Please open an issue if you discover any missing steps.

## Setup

The build produces a file `qubes_ssh_agent.tar.bz2` that can be extracted to `/var/lib/qubes/vm-kernels`. See e.g. https://github.com/mirage/qubes-mirage-firewall#deploy on how to deploy the unikernel.

### Dom0

Create a file `/etc/qubes-rpc/policy/qubes.SshAgent` with the policy you desire. A good start is `$anyvm $anyvm ask`.

### Client DomU

Copy `ssh-agent.socket` and `ssh-agent@.service` to `/etc/systemd/system/` in the client VM, and run `systemctl start ssh-agent.socket; systemctl enable ssh-agent.socket`. Then configure your shell to set `SSH_AUTH_SOCK` to `/var/run/mirage-ssh-agent/qrexec.sock`.
