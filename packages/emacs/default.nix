{ lib
, stdenv
, fetchurl

# Build-time
, pkgconfig

# Required build dependencies
, ncurses

# Features
, acl
, libxml2
, zlib

, tlsSupport ? false
, gnutls

# X
, x11Support ? true
, x11Toolkit ? if x11Support then "lucid" else "no"
, libXaw ? null
, libXext ? null
, libXft ? null
, libXmu ? null
, libXt ? null

# Image formats
, libXpm ? null

, includeEmacsCSource ? true
}:

with lib;

stdenv.mkDerivation rec {
  name = "emacs-${version}";
  version = "26.1";
  emacsVersion = "26.1"; # in case version contains -rc1

  src = fetchurl {
    urls = [
      "ftp://alpha.gnu.org/gnu/emacs/pretest/emacs-${version}.tar.xz"
      "mirror://gnu//emacs/emacs-${version}.tar.xz"
    ];
    sha256 = "0b6k1wq44rc8gkvxhi1bbjxbz3cwg29qbq8mklq2az6p1hjgrx0w";
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ pkgconfig ];

  buildInputs = [ ncurses ]
    ++ [ acl libxml2 zlib ]
    ++ optional tlsSupport gnutls
    ++ optionals x11Support [ libXaw libXext libXft libXmu libXt libXpm ];

  configureFlags =
    [ "--disable-build-details"

      # Features
      "--with-dbus=no"
      "--with-file-notification=inotify"
      "--with-gif=no"
      "--with-gsettings=no"
      "--with-jpeg=no"
      "--with-lcms2=no"
      "--with-libsystemd=no"
      "--with-png=no"
      "--with-rsvg=no"
      "--with-sound=no"
      "--with-tiff=no"
      "--without-modules"
      "--without-pop"

      # Handle this ourselves
      "--without-compress-install"

      "--with-x-toolkit=${x11Toolkit}"
    ]
    ++ optional (!x11Support) "--without-x"
    ++ optional (!tlsSupport) "--with-gnutls=no"
    ;

  postPatch = ''
    sed -i Makefile.in lib-src/Makefile.in -e 's,/bin/pwd,pwd,g'

    # Run emacs dumper in a clean environment
    sed -i src/Makefile.in -e 's,RUN_TEMACS =.*,RUN_TEMACS = env -i ./temacs,g'
  '';
  # TODO: teach cc-wrapper about nopie
  #sed -i src/Makefile.in -e 's,TEMACS_LDFLAGS = ,& -nopie,'

  postFixup = ''
    rm -rf $out/var

    gzip -9n "$out/share/info/"*.info

    find $out/share/emacs/${emacsVersion}/lisp -type f -name '*.elc' \
      | sed 's,.elc$,.el,g' \
      | xargs -P$NIX_BUILD_CORES -n1 gzip -9n


    cat >$out/share/emacs/site-lisp/site-start.el <<EOF
    (add-to-list 'load-path
                 (mapcar (lambda (x) (concat x "/share/emacs/site-lisp/"))
                         (split-string (or (getenv "NIX_PROFILES") ""))))
    EOF
  '' + optionalString includeEmacsCSource ''
    csrcdir=$out/share/emacs/${emacsVersion}/src
    mkdir -p "$csrcdir"
    cp -t "$csrcdir" "src/"*.[chm]

    cat >>$out/share/emacs/site-lisp/site-start.el <<EOF
    (setq find-function-C-source-directory "$csrcdir")
    EOF
  '';

  passthru = {
    inherit
      x11Support
      x11Toolkit
      tlsSupport
    ;
  };

  meta = {
    description = "Extensible, customizable, self-documenting real-time display editor";
    homepage = "https://www.gnu.org/software/emacs/";
    license = licenses.gpl3Plus;
    platforms = platforms.all;
 };
}
