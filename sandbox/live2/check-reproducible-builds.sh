#! /bin/sh

set -eu

attrs=(initramfs packageEnv moduleTree storeImage livefs)

for attr in ${attrs[@]} ; do
    nix-build --no-out-link -A $attr
done

for attr in ${attrs[@]} ; do
    nix-build --no-out-link --check -A $attr
done
