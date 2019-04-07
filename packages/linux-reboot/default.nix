{ stdenv }:

stdenv.mkDerivation rec {
  name = "linux-reboot-0";

  src = ./linux_reboot.c;

  unpackPhase = ":";

  buildPhase = ''
    cc -pipe -Os -Wall -Werror -o halt $src
  '';

  installPhase = ''
    install -D -m 555 halt $out/bin/halt
  '';
}
