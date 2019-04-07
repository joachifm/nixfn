{ stdenv, fetchurl }:

let
  version = "2017-09-07";
  rev = "d1de64e50fc25d9e43a479c9a74c020daa1281e4";
  sha256 = "0gbn59b24d17g01f2xf6153ck0vh3w91gsff17z025rk9pvjw5mg";
in

stdenv.mkDerivation rec {
  name = "void-runit-${version}";

  src = fetchurl {
    url = "https://github.com/voidlinux/void-runit/archive/${rev}.tar.gz";
    inherit sha256;
  };

  configurePhase = ":";

  buildPhase = ''
    cc $NIX_CFLAGS_COMPILE -s -Os -o pause pause.c
  '';

  installPhase = ''
    install -m 555 -Dt $out/bin pause
    install -m 444 -Dt $out/share/man/man1 pause.1
  '';

  meta = {
    homepage = "https://github.com/voidlinux/void-runit/";
  };
}
