# TODO: PC/SC for smartcards

{ lib
, stdenv
, fetchurl
, fetchpatch

, pkgconfig

# Platform dependent
, libnl ? null
, libpcap ? null

# Optional: TLS support
, tlsSupport ? true
, openssl ? null

# Optional: DBus support
, dbusSupport ? false
, dbus ? null
}:

with lib;

stdenv.mkDerivation rec {
  name = "wpa_supplicant-${version}";
  version = "2.6";

  src = fetchurl {
    # https://w1.fi/releases/wpa_supplicant-A.B.tar.gz.asc
    url = "https://w1.fi/releases/wpa_supplicant-${version}.tar.gz";
    sha256 = "0l0l5gz3d5j9bqjsbjlfcv4w4jwndllp9fmyai4x9kg6qhs6v4xl";
  };

  patches = optional tlsSupport
    (fetchpatch {
      url = https://gitweb.gentoo.org/repo/gentoo.git/plain/net-wireless/wpa_supplicant/files/wpa_supplicant-2.6-libressl.patch;
      sha256 = "1c5fqzwsy1ksp7bqr3k39dv5i7hdxgswkd1z7gkwjskp9856447q";
      name = "wpa_supplicant-2.6-libressl.patch";
    });

  nativeBuildInputs = [ pkgconfig ];

  buildInputs =
       optional stdenv.isLinux libnl
    ++ optional tlsSupport openssl
    ++ optional (!stdenv.isLinux) libpcap;

  configurePhase = ''
    cd wpa_supplicant

    cp defconfig .config
    cat >>.config <<EOF
    ${optionalString stdenv.isLinux ''
      CONFIG_DRIVER_NL80211=y
      CONFIG_LIBNL32=y
      CONFIG_DRIVER_ATHEROS=y
      CONFIG_DRIVER_HOSTAP=y
      CONFIG_DRIVER_WEXT=y
      CONFIG_DRIVER_WIRED=y
    ''}
    ${optionalString stdenv.isFreeBSD ''
      CONFIG_DRIVER_BSD=y
    ''}
    ${optionalString stdenv.isOpenBSD ''
      CONFIG_DRIVER_OPENBSD=y
    ''}

    CONFIG_DRIVER_NONE=y

    # IEEE 802.1X
    CONFIG_IEEE80211W=y
    CONFIG_IEEE80211R=y

    # Background scanning
    CONFIG_BGSCAN_SIMPLE=y
    CONFIG_BGSCAN_LEARN=y

    # Authentication methods
    # EAP-MD5
    CONFIG_EAP_MD5=y
    # EAP-MSCHAPv2
    CONFIG_EAP_MSCHAPV2=y
    # EAP-TLS
    CONFIG_EAP_TLS=y
    # EAP-PEAP
    CONFIG_EAP_PEAP=y
    # EAP-TTLS
    CONFIG_EAP_TTLS=y
    # EAP-FAST
    # (Requires OpenSSL >=1.0)
    CONFIG_EAP_FAST=y
    # EAP-GTC
    CONFIG_EAP_GTC=y
    # EAP-OTP
    CONFIG_EAP_OTP=y
    # EAP-LEAP
    CONFIG_EAP_LEAP=y

    # Use default ctrl iface for platform
    CONFIG_CTRL_IFACE=y

    CONFIG_BACKEND=file
    CONFIG_NO_CONFIG_WRITE=y

    # Select event loop implementation
    CONFIG_ELOOP=eloop
    ${if stdenv.isLinux
      then ''CONFIG_ELOOP_EPOLL=y''
      else if stdenv.isFreeBSD
      then ''CONFIG_ELOOP_KQUEUE=y''
      else ""}

    # Select layer 2 packet implementation
    #
    # Note: selecting CONFIG_DRIVER_BSD implies L2_PACKET=freebsd
    CONFIG_L2_PACKET=${if stdenv.isLinux
      then "linux"
      else if stdenv.isFreeBSD
      then "freebsd"
      else "pcap"}

    # Select TLS implementation
    CONFIG_TLS=openssl
    CONFIG_TLSV11=y
    CONFIG_TLSV12=y

    ${optionalString dbusSupport ''
      # New-style dbus control iface (fi.w1.hostap.wpa_supplicant)
      CONFIG_CTRL_IFACE_DBUS_NEW=y
    ''}

    # TODO: implement me
    #
    # See 'Privilege separation' in README
    #CONFIG_PRIVSEP=y

    # Rely on host to provide good entropy
    CONFIG_NO_RANDOM_POOL=y
    EOF
  '';

  installFlags = [
    "DESTDIR="
    "INCDIR=${placeholder "out"}/include"
    "BINDIR=${placeholder "out"}/bin"
    "LIBDIR=${placeholder "out"}/lib"
  ];

  passthru = {
    inherit dbusSupport tlsSupport;
  };

  meta = {
    description = "A WPA/WPA2/IEEE 802.1X Supplicant";
    homepage = "https://w1.fi/wpa_supplicant/";
    license = with licenses; [ bsd3 gpl2 ];
    broken =
      (stdenv.isLinux && libnl == null) ||
      (!stdenv.isLinux && libpcap == null) ||
      (tlsSupport && openssl == null) ||
      (dbusSupport && dbus != null);
  };
}
