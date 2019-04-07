{ lib
, stdenv
, fetchurl

# Build-time
, pkgconfig

# Required
, libuuid

# Strictly optional
, device-mapper

# Optional features
, withReadline ? false
, readline ? null
}:

with stdenv.lib;

stdenv.mkDerivation rec {
  name = "parted-${version}";
  version = "3.2";

  src = fetchurl {
    url = "mirror://gnu/parted/parted-${version}.tar.xz";
    sha256 = "1r3qpg3bhz37mgvp9chsaa3k0csby3vayfvz8ggsqz194af5i2w5";
  };

  nativeBuildInputs = [ pkgconfig ];

  buildInputs = [ device-mapper libuuid ]
    ++ optional withReadline readline;

  configureFlags = [ "--disable-nls" ]
    ++ optional (!withReadline) "--without-readline";

  passthru = {
    inherit withReadline;
  };

  meta = with lib; {
    description = "Create, destroy, resize, check, and copy partitions";
    homepage = "https://www.gnu.org/software/parted/";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
