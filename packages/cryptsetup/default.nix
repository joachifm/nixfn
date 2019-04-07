{ lib
, stdenv
, fetchurl

, pkgconfig

, device-mapper
, json_c
, libargon2
, libgcrypt
, libuuid
, popt
}:

stdenv.mkDerivation rec {
  name = "cryptsetup-${version}";
  version = "${majVer}.3";
  majVer = "2.0";

  src = fetchurl {
    url = "mirror://kernel/linux/utils/cryptsetup/v${majVer}/${name}.tar.xz";
    sha256 = "1m01wl8njjraz69fsk97l3nqfc32nbpr1la5s1l4mzzmq42clv2d";
  };

  outputs = [ "dev" "out" "man" ];

  nativeBuildInputs = [ pkgconfig ];

  buildInputs = [ device-mapper json_c libargon2 libgcrypt libuuid popt ];

  configureFlags = [
    "--disable-nls"
    "--with-crypto_backend=gcrypt"
    "--enable-libargon2"
  ];

  postInstall = ''
    rm $out/lib/libcryptsetup.la
  '';

  meta = with lib; {
    description = "User space tools for dm-crypt";
    homepage = "https://gitlab.com/cryptsetup/cryptsetup/";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
