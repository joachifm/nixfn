# TODO: cracklib support

{ lib, stdenv, fetchurl, pkgconfig }:

with lib;

stdenv.mkDerivation rec {
  name = "Linux-PAM-${version}";
  version = "1.3.1";

  src = fetchurl {
    url = "https://github.com/linux-pam/linux-pam/releases/download/v${version}/Linux-PAM-${version}.tar.xz";
    sha256 = "1nyh9kdi3knhxcbv5v4snya0g3gff0m671lnvqcbygw3rm77mx7g";
  };

  outputs = [ "dev" "out" "man" "doc" ];

  nativeBuildInputs = [ pkgconfig ];

  configureFlags = [
    "--disable-nls"
    "--enable-db=no"
  ];

  installFlags = [ "includedir=${placeholder "dev"}/include/security" ];

  postInstall = ''
    mkdir -p $doc/share/doc/Linux-PAM/examples
    mv $out/etc $doc/share/doc/Linux-PAM/examples
  '';

  meta = {
    description = "Pluggable Authentication Modules";
    homepage = "http://www.linux-pam.org/";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
