{ lib
, stdenv
, fetchurl

# Build-time
, pkgconfig

# Feature: setpriv
, libcap-ng

# Feature: login &c
, pam
}:

stdenv.mkDerivation rec {
  name = "util-linux-${version}";
  version = "${majorVersion}.1";
  majorVersion = "2.32";

  src = fetchurl {
    url = "mirror://kernel/linux/utils/util-linux/v${majorVersion}/util-linux-${version}.tar.xz";
    sha256 = "1ck7d8srw5szpjq7v0gpmjahnjs6wgqzm311ki4gazww6xx71rl6";
  };

  propagatedBuildOutputs = [ "lib" ];

  outputs = [ "dev" "out" "lib" "man" "doc" "bashcompletions" ];

  nativeBuildInputs = [ pkgconfig ];

  buildInputs = [ libcap-ng pam ];

  configureFlags = [
    "--sbindir=${placeholder "out"}/bin"
    "--localstatedir=/run"
    "--with-bashcompletiondir=${placeholder "bashcompletions"}/share/bash-completion/completions"

    # No native language support, please
    "--disable-nls"

    # Work around chown shenanigans during install
    "--disable-makeinstall-chown"
    "--disable-makeinstall-setuid"

    "--without-libz"
    "--without-ncurses"
    "--without-ncursesw"
    "--without-readline"
    "--without-udev"
    "--without-user"

    "--without-python"
  ];

  postConfigure = ''
    # the build system insists on putting these under exec_prefix ...
    sed -i Makefile \
        -e "s,usrbin_execdir = .*,usrbin_execdir=$out/bin," \
        -e "s,usrlib_execdir = .*,usrlib_execdir=$lib/lib," \
        -e "s,usrsbin_execdir = .*,usrsbin_execdir=$out/bin,"
  '';

  meta = with lib; {
    description = "A collection of Linux utilities";
    homepage = "https://www.kernel.org/pub/linux/utils/util-linux/";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    priority = 2; # overrides kill from coreutils, login and su from shadow
  };
}
