let
  /* Last updated 2018-18-21 */
  nixpkgsrev = "4b649a99d8461c980e7028a693387dc48033c1f7";
  nixexprs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs-channels/archive/${nixpkgsrev}.tar.gz";
    sha256 = "0iy2gllj457052wkp20baigb2bnal9nhyai0z9hvjr3x25ngck4y";
  };

  nixpkgsFn = import nixexprs;

  buildPackages = (nixpkgsFn { }).buildPackages;

  inherit (buildPackages)
    buildEnv
    runCommand
    stdenv
    stdenvNoCC
    writeScript
    writeText
  ;

  singleton = elt: if builtins.isList elt then elt else [ elt ];

  singleton1 = elt: [ elt ];
in

rec {

  pkgs = nixpkgsFn {
    overlays = [
      (self: super: {
        glibcLocales = super.glibcLocales.override {
          inherit (config) locales;
          allLocales = false;
        };

        busyboxStatic = super.busybox.override {
          enableStatic = true;
          useMusl = true;
        };
      })
    ];
  };

  /*
   * CONFIG
   */

  config.consoleKeymap = "no-latin1";

  config.locales = [
    "en_US.UTF-8/UTF-8"
    "nb_NO.UTF-8/UTF-8"
  ];

  config.timeZone = "Europe/Oslo";

  config.hostname = "linix";

  config.linuxPackages = pkgs.linuxPackages;

  /*
   * ARTEFACTS
   */

  binaryKeymaps = runCommand "binary-keymaps"
    { nativeBuildInputs = with buildPackages; [ kbd ];
      inherit (buildPackages) kbd;
      keymaps = [ "defkeymap" ] ++ singleton config.consoleKeymap;
    }
    ''
    for kmap in $keymaps ; do
      loadkeys -b "$kbd/share/keymaps/i386/qwerty/$kmap.map.gz" | gzip -v -9n > "$kmap.bmap.gz"
    done
    install -m 444 -Dt $out/share/keymaps ./*.bmap.gz
    '';

  initramfs = runCommand "initramfs"
    { nativeBuildInputs = with buildPackages; [ cpio ];
      inherit (pkgs) busyboxStatic;
      fileName = "initramfs.img";
    }
    ''
    mkdir root && cd root

    echo "Creating initramfs root hierarchy ..."
    mkdir -m 755 bin dev lib mnt proc run sys
    mkdir -m 700 root

    echo "Copying static busybox ..."
    cp $busyboxStatic/bin/busybox lib/busybox
    $busyboxStatic/bin/busybox --list | while IFS= read -r app ; do
      ln -v lib/busybox bin/$app
    done

    echo "Generating initramfs init ..."
    cat >init <<EOF
    #! /bin/sh -eu

    rescue() {
      echo "Entering rescue shell!"
      exec setsid -c sh -l
    }
    trap rescue EXIT INT QUIT TERM

    umask 022

    set -a
    HOME=/root
    PATH=/bin
    set +a

    mount proc /proc -t proc
    mount sys /sys -t sysfs
    mount dev /dev -t devtmpfs
    mkdir /dev/pts
    mount devpts /dev/pts -t devpts
    mount run /run -t tmpfs

    setsid -c sh -l

    trap - EXIT INT QUIT TERM
    killall5 -KILL

    poweroff -nf

    mount --move /dev /mnt/dev
    mount --move /proc /mnt/proc
    mount --move /run /mnt/run
    mount --move /sys /mnt/sys

    exec $(command -v switch_root) /mnt
    EOF
    bash --posix -n init
    chmod +x init

    echo "Creating initramfs image ..."
    find . -mindepth 1 -exec touch -h -d @1 '{}' + -print0 \
      | LC_ALL=C sort -z \
      | cpio -0 -H newc -o --reproducible -R +0.+0 \
      | gzip -v -1n \
      > $NIX_BUILD_TOP/$fileName

    echo "Copying outputs ..."
    install -v -m 444 -Dt $out $NIX_BUILD_TOP/$fileName
  '';

  systemSwPath = buildEnv {
    name = "system-sw-path";
    paths = with pkgs; [
      binaryKeymaps
      glibcLocales
      tzdata

      busyboxStatic
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/share"
    ];
  };

  systemProfile = runCommand "system-profile"
    { inherit systemSwPath;
      inherit (config) timeZone;
    }
    ''
    mkdir build && cd build

    cat >activate << EOF
    #! /bin/sh -eu

    readonly profile=$out

    umask 022
    unset IFS

    set -a
    PATH=\$profile/sw/bin:/bin
    set +a

    ln_s() {
      local target=\''${1?Link target}
      local name=\''${2?Link name}
      local templink=\$(mktemp)
      ln -sf "\$target" "\$templink"
      mv "\$templink" "\$name"
    }

    if [ ! -L /run/booted-system ] ; then
      ln_s \$profile /run/booted-system
    fi
    ln_s \$profile /run/current-system
    EOF
    chmod +x activate

    ln -s "$systemSwPath" sw

    cat >environment << EOF
    CURL_CA_BUNDLE=/run/current-system/sw/etc/ssl/certs/ca-bundle.crt
    LANG=en_US.UTF-8
    LC_COLLATE=C
    LC_MESSAGES=C
    LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive
    PATH=/run/current-system/sw/bin:/bin
    TZ=:/run/localtime
    TZDIR=/run/current-system/sw/share/zoneinfo
    EOF

    cat >profile <<EOF
    umask 022
    . $out/environment
    unset IFS MANPATH TERMCAP
    EOF

    cat >init << EOF
    #! /bin/sh -eu

    readonly profile=$out

    umask 022
    unset IFS

    set -a
    PATH=\$profile/sw/bin:/bin
    set +a

    mount_robind() {
      local what=\''${1?What}
      local where=\''${2:-$what}
      mount "\$what" "\$where" -o bind
      mount "\$where"          -o remount,bind,ro
    }

    mount proc /proc -t proc
    mount sys /sys -t sysfs
    mount dev /dev -t devtmpfs
    mkdir /dev/pts
    mount devpts /dev/pts -t devpts
    mount run /run -t tmpfs
    install -d /run/tmp -m 1777
    mount tmp /run/tmp -t tmpfs
    install -d /run/shm -m 1777
    mount shm /run/shm -t tmpfs

    echo "$timeZone" > /run/localtime
    hwclock --systz

    echo "$hostname" > /proc/sys/kernel/hostname

    install -d /nix/store -m 1775 -o root -g nixbld
    mount_robind /nix/store
    EOF
    chmod +x init
    bash --posix -n init

    mkdir $out
    tar cp . | tar x -C $out
    '';

  vm.bzImage = "${config.linuxPackages.kernel}/bzImage";

  vm.initrd = "${initramfs}/${initramfs.fileName}";

  vm.cmdline = [
    "audit=0"
    "apparmor=0"
    "console=ttyS0"
    "quiet"
    "oops=panic"
    "panic=-1"
  ];

  vm.run = writeScript "run" ''
    #! /bin/sh -eu
    exec qemu-system-x86_64 \
      -no-reboot \
      -nographic \
      -cpu host \
      -enable-kvm \
      -kernel '${vm.bzImage}' \
      -initrd '${vm.initrd}' \
      -append '${toString vm.cmdline}' \
      "$@"
  '';

  run-vm = vm.run;
}
