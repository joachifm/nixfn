#! /bin/sh -eu

rm -f run/live.fs
nix run -f default.nix runVm -c run-vm
