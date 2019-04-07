{ stdenv, fetchurl, perl, libunwind }:

stdenv.mkDerivation rec {
  name = "strace-${version}";
  version = "4.24";

  src = fetchurl {
    # sigurl=https://github.com/strace/strace/releases/download/v4.24/strace-4.24.tar.xz.asc
    urls = [
      "https://github.com/strace/strace/releases/download/v${version}/strace-${version}.tar.xz"
    ];
    sha256 = "0d061cdzk6a1822ds4wpqxg10ny27mi4i9zjmnsbz8nz3vy5jkhz";
  };

  outputs = [ "out" "extras" ];

  buildInputs = [ perl libunwind ]; # support -k

  postInstall = ''
    mkdir -p $extras/bin
    mv $out/bin/strace-{graph,log-merge} $extras/bin
  '';

  meta = with stdenv.lib; {
    description = "A system call tracer for Linux";
    homepage = "https://strace.io/";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
