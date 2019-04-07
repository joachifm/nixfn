# re: virtfs: https://www.linux-kvm.org/page/VirtFS
# re: jemalloc: https://lists.gnu.org/archive/html/qemu-devel/2015-06/msg05265.html

{ stdenv
, fetchurl
, python2
, pkgconfig

, bison
, flex

, glib
, pixman

, attr
, jemalloc
, libaio
, libcap
, libcap-ng
, libseccomp
, libssh2
, libusb
, vde2
}:

with stdenv.lib;

stdenv.mkDerivation rec {
  name = "qemu-${version}";
  version = "2.12.0";

  src = fetchurl {
    url = "https://download.qemu.org/qemu-${version}.tar.xz";
    sha256 = "1z66spkm1prvhbq7h5mfnp0i6mmamsb938fqmdfvyrgzc7rh34z6";
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ bison flex pkgconfig python2 ];

  hardeningDisable = [ "stackprotector" ];

  buildInputs = [
    attr
    glib
    jemalloc
    libaio
    libcap
    libcap-ng
    libseccomp
    libssh2
    libusb
    pixman
    vde2
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"

    "--python=python2"
    "--smbd=smbd"

    "--cpu=x86_64"
    "--target-list=x86_64-softmmu"
    "--enable-coroutine-pool"
    "--audio-drv-list="

    "--disable-bluez"
    "--disable-brlapi"
    "--disable-curses"
    "--disable-gcrypt"
    "--disable-gnutls"
    "--disable-gtk"
    "--disable-hax"
    "--disable-nettle"
    "--disable-sdl"
    "--disable-spice"
    "--disable-vnc"
    "--disable-vte"
    "--disable-xen"

    "--disable-live-block-migration"
    "--disable-replication"
    "--disable-tpm"
  ];

  meta = {
    description = "A generic and open source machine emulator and virtualizer";
    homepage = "https://www.qemu.org/";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
  };
}
