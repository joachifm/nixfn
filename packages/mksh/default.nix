# TODO: support test phase

{ lib
, stdenv
, fetchurl

# Required by the test suite
, perl

# Whether to build a "Legacy Korn Shell" variant, suitable for use as a
# reasonably compliant POSIX /bin/sh.
, legacy ? false

# Static build support
, static ? false
, musl ? null
}:

with lib;

let
  variant = if legacy then "lksh" else "mksh";
in

stdenv.mkDerivation rec {
  name = "${variant}-${version}";
  version = "56c";
  srcName = "mksh-R${version}";
  src = fetchurl {
    urls = [
      "https://www.mirbsd.org/MirOS/dist/mir/mksh/${srcName}.tgz"
      "http://pub.allbsd.org/MirOS/dist/mir/mksh/${srcName}.tgz"
    ];
    sha256 = "0xzv5b83b8ccn3d4qvwz3gk83fi1d42kphax1527nni1472fp1nx";
  };

  # error: undefined reference to '__longjmp_chk' &c
  hardeningDisable = optional static "fortify";

  outputs = [ "out" "man" ] ++ optional (!legacy) "doc";

  buildInputs = optional doCheck perl;

  buildFlags = [ "-r" "-c lto" ] ++ optional legacy "-L";

  CFLAGS = optionals static [
    "-isystem ${musl}/include"
    "-B${musl}/lib"
    "-L${musl}/lib"
  ];

  LDSTATIC = optionalString static "-static";

  CPPFLAGS = [
    "-DMKSH_ASSUME_UTF8"
    "-DMKSH_DISABLE_DEPRECATED"
    "-DMKSH_DONT_EMIT_IDSTRING"
  ]
  ++ optionals legacy [
    "-DMKSH_BINSHPOSIX"
  ];

  buildPhase = "sh ./Build.sh $buildFlags";

  installPhase = ''
    mkdir -p $out/bin
    cp ${variant} $out/bin/${variant}

    ${optionalString (!legacy) ''
      mkdir -p $doc/share/mksh
      cp dot.mkshrc $doc/share/mksh/mkshrc
    ''}

    mkdir -p $man/share/man/man1
    cp ${variant}.1 $man/share/man/man1/
  '';

  # TODO: test suite fails
  doCheck = false;
  checkPhase = "./test.sh -f";

  passthru = {
    inherit legacy;
    shellPath = "/bin/${variant}";
  };

  meta = with stdenv.lib; {
    description = ''${if legacy then "Legacy" else "MirBSD"} Korn shell'';
    homepage = https://www.mirbsd.org/MirOS/;
    license = licenses.bsd3;
    platforms = platforms.unix;
    broken = (static && musl == null);
  };
}
