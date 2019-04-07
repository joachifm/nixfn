/**
 * @param self  the final package set
 * @param super the previous package set
 */
self: super:

let
  stdenvCustom = import ./stdenv.nix {
    prevStdenv = super.stdenv;
  };

  callPackage = super.newScope (self // {
    stdenv = stdenvCustom;
    stdenvNoCC = stdenvCustom.override { cc = null; };
  });
in

{
  busyboxStatic = super.busybox.override {
    enableStatic = true;
  };

  cryptsetup = callPackage ./cryptsetup { };

  edk2-ovmf = callPackage ./edk2-ovmf { };

  emacs = callPackage ./emacs { };

  emacsNoX11 = self.emacs.override {
    x11Support = false;
  };

  emacsMinimal = self.emacs.override {
    includeEmacsCSource = false;
    tlsSupport = false;
    x11Support = false;
  };

  intel-ucode = callPackage ./intel-ucode { };

  iucode-tool = callPackage ./iucode-tool { };

  Linux-PAM = callPackage ./Linux-PAM { };

  lkshStatic = self.mksh.override {
    legacy = true;
    static = true;
  };

  linux-reboot = callPackage ./linux-reboot { };

  inherit (callPackage ./lvm2 { })
    device-mapper
    lvm2
  ;

  mksh = callPackage ./mksh { };

  parted = callPackage ./parted { };

  pcsclite = super.pcsclite.overrideAttrs (old: {
    configureFlags = old.configureFlags ++ [ "--disable-libsystemd" ];
  });

  qemu_x64 = callPackage ./qemu { };

  runit-sysvinit = callPackage ./runit-sysvinit { };

  seabios = callPackage ./seabios { };

  sinit-sysvinit = callPackage ./sinit-sysvinit { };

  strace = callPackage ./strace { };

  util-linux = callPackage ./util-linux { };

  void-runit = callPackage ./void-runit { };

  wpa-supplicant = callPackage ./wpa_supplicant { };


  ### VIRTUAL PROVIDERS

  pam = self.Linux-PAM;

  udev = self.eudev;

  systemd = null;

  ### ALIAS

  libutil-linux = self.util-linux.dev;

  libblkid = self.libutil-linux;

  libuuid = self.libutil-linux;

  libcap-ng = self.libcap_ng;
}
