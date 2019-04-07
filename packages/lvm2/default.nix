# TODO: unify lvm2 and device-mapper, the latter should be a separate output

# The motivation for building device-mapper and lvm2 as separate artefacts is to
# allow other packages to depend only on the low-level volume management provided
# by device-mapper (e.g., cryptsetup).

{ lib
, stdenv
, fetchurl

# Build-time
, pkgconfig
, which

# Required
, libuuid

# Optional
, thinSupport ? true
, thin-provisioning-tools ? null

, udevSupport ? true
, udev ? null
}:

with lib;

let
  version = "2.02.177";
  dmVersion = "1.02.146";

  src = fetchurl {
    # ftp://sources.redhat.com/pub/lvm2/releases/LVM2.${version}.tgz.asc
    # ftp://sources.redhat.com/pub/lvm2/releases/sha512.sum
    urls = [
      "ftp://sources.redhat.com/pub/lvm2/releases/LVM2.${version}.tgz"
      "ftp://mirrors.kernel.org/sourceware/lvm2/releases/LVM2.${version}.tgz"
      "http://ftp.gwdg.de/pub/linux/sources.redhat.com/lvm2/releases/LVM2.${version}.tgz"
    ];
    sha256 = "1wl0isn0yz5wvglwylnlqkppafwmvhliq5bd92vjqp5ir4za49a0";
  };

  commonConfigureFlags = [
    "--sbindir=${placeholder "out"}/bin"
    "--enable-pkgconfig"
    "--disable-readline"
  ] ++ optionals udevSupport [
    "--disable-udev-systemd-background-jobs"
    "--enable-udev_rules"
    "--enable-udev_sync"
    "--enable-udev-rule-exec-detection"
  ];
in

rec {

  device-mapper = stdenv.mkDerivation rec {
    name = "device-mapper-${version}";
    version = dmVersion;
    inherit src;

    nativeBuildInputs = [ pkgconfig which ];
    buildInputs = [ libuuid ]
      ++ optional udevSupport udev;

    configureFlags = commonConfigureFlags ++ [
      "--enable-cmdlib"
      "--enable-dmeventd"
    ];

    buildPhase = ''
      make "''${makeFlags[@]}" device-mapper
    '';

    installPhase = ''
      runHook preInstall
      make "''${makeFlags[@]}" install_device-mapper
      runHook postInstall
    '';

    # TODO: blkdeactivate requires lots of patching to actually work
    #
    # Note: deleting line 36 is a rather fragile way of patching out a redundant
    # check of ENV{DM_SBIN_PATH}.
    postInstall = ''
      rm $out/bin/blkdeactivate
    '' + optionalString udevSupport ''
      dm_sbin_path=$out/bin
      sed -i $out/lib/udev/rules.d/10-dm.rules \
          -e 's,\(ENV{DM_SBIN_PATH}\)=.*,\1="'$dm_sbin_path'",' \
          -e '36d'
    '';

    passthru = {
      inherit udevSupport;
    };

    meta = with stdenv.lib; {
      description = "Device mapper user-land tools";
      homepage = "https://sourceware.org/dm/";
      license = licenses.gpl2;
      platforms = platforms.linux;
      broken = (udevSupport && udev == null);
    };
  };

  lvm2 = stdenv.mkDerivation rec {
    name = "lvm2-${version}";
    inherit src version;

    nativeBuildInputs = [ pkgconfig which ];

    buildInputs = [ device-mapper libuuid ]
      ++ optional thinSupport thin-provisioning-tools
      ++ optional udevSupport udev;

    configureFlags = commonConfigureFlags ++ [
      "--with-cluster=none"
      "--with-clvmd=none"
      "--with-lvm1=none"

      "--enable-applib"
      "--enable-cmdlib"
      "--enable-lvmetad"

      # Built-in modules
      "--with-cache=internal"
      "--with-mirrors=internal"
      "--with-snapshots=internal"
      ''--with-thin=${if thinSupport then "internal" else "none"}''

      # Normally, lvm wants to write metadata backup files &c to /etc, we'll
      # write to /var instead to better support read-only /etc.
      "--with-default-system-dir=/var/lib/lvm"

      # Read configuration from /etc
      "--with-confdir=/etc/lvm"

      # Default run-time state directories
      "--with-default-locking-dir=/run/lock/lvm"
      "--with-default-pid-dir=/run"
      "--with-default-run-dir=/run/lvm"
    ];

    installPhase = ''
      runHook preInstall
      make "''${makeFlags[@]}" -C liblvm install
      make "''${makeFlags[@]}" DEFAULT_SYS_DIR=$out/etc/lvm confdir=$out/etc install_lvm2
      runHook postInstall
    '';

    # Note: deleting line 19 is a fragile way of patching out a redundant check of
    # ENV{LVM_SBIN_PATH}.
    #
    # TODO: fsadm, lvmconf, lvmdump extensive patching to be useful
    # TODO: consider replacing with dummy programs or something ...?
    postInstall = ''
      rm $out/bin/fsadm
      rm $out/bin/lvmconf
      rm $out/bin/lvmdump

      mkdir -p $out/share/doc/lvm2
      mv $out/etc $out/share/doc/lvm2/etc
    '' + optionalString udevSupport ''
      lvm_sbin_path=$out/bin
      sed -i $out/lib/udev/rules.d/69-dm-lvm-metad.rules \
          -e 's,\(ENV{LVM_SBIN_PATH}\)=.*,\1="'$lvm_sbin_path'",' \
          -e '19d'
    '';

    passthru = {
      inherit thinSupport udevSupport;
    };

    meta = with stdenv.lib; {
      description = "LVM2 user-land tools";
      homepage = "https://sourceware.org/lvm2/";
      license = licenses.gpl2;
      platforms = platforms.linux;
      broken = (thinSupport && thin-provisioning-tools == null) ||
        (udevSupport && udev == null);
    };
  };

}
