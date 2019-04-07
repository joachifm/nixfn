/*
 * A UEFI bootable live system capable of updating and replicating
 * itself in-place, as well as install a system onto a target machine.
 */

{ buildPackages, hostPackages }:

let
  inherit (buildPackages)
    lib
    buildEnv
    runCommand
    writeScript
  ;
in

with lib;

{ isReleaseBuild ? false
, isVmBuild ? false
}:

rec {

  config.isReleaseBuild = isReleaseBuild;

  config.isVmBuild = isVmBuild;

  config.shellPrompt = "live# ";

  config.consoleKeymap = "no-latin1";

  config.hostname = "linix-live";

  config.sysctls = { };

  config.linuxPackages = hostPackages.linuxPackages_latest;

  config.systemPackages = with hostPackages; [
    buildLib.binaryKeymaps
    glibcLocales
    tzdata
    udevRules
    cacert

    cryptsetup
    device-mapper
    eudev
    kmod
    lvm2

    socklog

    ddrescue
    hdparm
    smartmontools

    lzip

    dhcpcd
    iw
    wpa_supplicant
    unbound

    man-db
    man-pages
    posix_man_pages

    dosfstools
    e2fsprogs
    gptfdisk
    mtools
    #xfsdump
    xfsprogs
    btrfs-progs

    nixUnstable
    patchelf

    lynx
    mg
    tmux

    gnupg
    minisign
    openssl.bin

    openssh
    tor

    file
    ldns.drill
    lshw
    strace
    tcpdump

    qrencode
    yubikey-personalization
  ];

   config.udevPackages = with hostPackages; map (x: x.udevRules or x.out) [
     device-mapper
     eudev
     lvm2
   ];

   udevRules = runCommand "udev-rules" { inherit (config) udevPackages; } ''
     echo "Creating system udev rules dir ..."
     dest=$out/etc/udev/rules.d
     mkdir -p "$dest"
     find $udevPackages -path '*/udev/rules.d/*.rules' -exec ln -s -t "$dest" '{}' '+' # */

     disabledRules=(60-cdrom_id.rules)
     for ruleName in ''${disabledRules[@]} ; do
       ln -nsf /dev/null $dest/$ruleName
     done
   '';

   config.modulesToLoad = [
     # Input
     "atkbd"

     # DM
     "dm-mod"
     "dm-crypt"
     "dm-integrity"
     "dm-verity"

     # USB 3.0
     "xhci-hcd"
     "xhci-pci"

     # Required to mount root
     "loop"
     "overlay"
     "squashfs"
     "vfat"
       "nls-cp437"
       "nls-iso8859-1"
   ]
   ++ optionals (!isVmBuild) [
     "aesni-intel"
     "crc32_pclmul"
     "ghash_clmulni_intel"
     "sha1-ssse3"
   ]
   ++ optionals (isVmBuild) [
     "virtio-blk"
     "virtio-crypto"
     "virtio-rng"
     "virtio-net"
     "virtio-pci"
     "9p"
     "9pnet"
     "9pnet-virtio"
   ];

  /*
   * A bootable live filesystem image.
   *
   * Usage:
   *   cat live.fs > /dev/memstick
   *
   * Layout:
   *   linux.efi
   *   initramfs.img
   *   startup.nsh
   *   nix-store.sqsh
   *
   * The system runs out of the initramfs.  The initramfs itself contains only
   * a static busybox binary, the init script, and kernel modules necessary to
   * mount the (compressed) Nix store.
   */
  build.livefs = runCommand "livefs"
    { nativeBuildInputs = with buildPackages; [
        dosfstools
        gptfdisk
        mtools
      ];

      bzImage = "${config.linuxPackages.kernel}/bzImage";

      kernelParams = [
        "audit=0"
        "apparmor=0"
        "elevator=deadline"
        "oops=panic"
        "panic=-1"
        "quiet"
        "intel_iommu=off"
        "transparent_hugepage=madvise"
      ]
      ++ lib.optionals isVmBuild [
        "console=ttyS0"
      ];

      nixStoreImage = "${nixStore}/nix-store.sqsh";

      initramfsImage = "${initramfs}/initramfs.img";

      intelUcode = "${hostPackages.intel-ucode}/intel-ucode.img";
    }
    ''
      set -eu -o pipefail

      root=livefs-root
      mkdir $root

      echo "Populating livefs root filesystem ..."

      cat >$root/startup.nsh <<EOF
      echo -off
      cls
      echo "Booting LINUX_LIVE"
      linux.efi initrd=\intel-ucode.img initrd=\initramfs.img $kernelParams
      EOF

      install -m 444 "$bzImage" $root/linux.efi
      install -m 444 "$initramfsImage" $root/initramfs.img
      install -m 444 "$nixStoreImage" $root/nix-store.sqsh
      gzip -c -v -9n "$intelUcode" > $root/intel-ucode.img

      # Note: imageSize is diskSize-2M to leave room at both ends of the disk
      echo "Creating livefs root filesystem image ..."
      imageSize=510M
      truncate -s "$imageSize" root.fs
      mkfs.vfat -F32 -n LINIX_LIVE --invariant root.fs
      find $root -mindepth 1 -exec touch -h -d "1980-01-01 00:00:01" '{}' '+'
      MTOOLS_SKIP_CHECK=1 \
      mcopy -i root.fs -bsvpm $root"/"* ::

      # Note: fixed -U UUID for reproducibility
      # Note: fixed -u UUID for reproducibility
      echo "Creating the livefs disk image ..."
      diskSize=512M
      truncate -s "$diskSize" live.fs
      sgdisk live.fs -Zo -U CFA0AFD7-A2C3-4589-B3A1-7001978AB502
      sgdisk live.fs \
        -n 0:0:0 \
        -u 0:4170FA63-9F6F-4C69-81B3-E4F2D23A864D \
        -c 0:"LINIX_LIVE" \
        -t 0:ef00

      # Note: need to skip first 1MB to avoid clobbering GPT
      # Note: need conv=notrunc to avoid clobbering GPT
      echo "Writing rootfs image to disk image ..."
      start=2048 # sectors
      obs=$((start * 512)) # sectors \times bytes-per-sector = 1MB
      dd if=root.fs of=live.fs obs=$obs seek=1 conv=sparse,notrunc

      echo "Checking disk image ..."
      sgdisk live.fs -evp

      echo "Copying outputs ..."
      install -m 444 -Dt $out live.fs
    '';

  nixStore = buildPackages.runCommand "nix-store"
    { nativeBuildInputs = with buildPackages; [ libfaketime squashfsTools ];
      inherit isReleaseBuild;
      closureInfo = buildPackages.closureInfo { rootPaths = [
      ]; };
    }
    ''
      set -eu -o pipefail

      echo "Creating Nix store image root ..."
      mkdir nix-store
      xargs -rn1 cp --sparse=always -a -t nix-store/ < $closureInfo/store-paths
      install -m 444 $closureInfo/registration nix-store/.registration

      echo "Creating excludes file for Nix store image ..."
      cat >excludes_file <<EOF
      */lib/pkgconfig
      */share/locale
      EOF

      if [[ $isReleaseBuild = 1 ]] ; then
        compress="-b 1M -comp xz -Xdict-size 100%"
      else
        compress="-comp gzip -Xcompression-level 1"
      fi

      # Note: no-fragments for reproducibility
      # Note: sort-file for reproducibility in the presence of duplicates
      # Note: all-root for reproducibility
      # Note: processors defaults to `nproc --all`
      echo "Creating compressed Nix store image ..."
      faketime -f "1970-01-01 00:00:01" \
      mksquashfs nix-store nix-store.sqsh \
        $compress \
        -processors ''${NIX_BUILD_CORES:-1} \
        -no-exports \
        -no-xattrs \
        -no-fragments \
        -no-duplicates \
        -all-root \
        -wildcards \
        -ef excludes_file

      du -s --si nix-store nix-store.sqsh

      install -m 444 -Dt $out nix-store.sqsh
    '';

  initramfs = runCommand "initramfs"
    { nativeBuildInputs = with buildPackages; [ cpio ];
      inherit isReleaseBuild;
      src = rootfs;
    }
    ''
      set -eu -o pipefail

      echo "Creating initramfs image ..."

      if [[ $isReleaseBuild = 1 ]] ; then
        compress="gzip -v -n9"
      else
        compress="cat"
      fi

      (cd "$src"
      find . -mindepth 1 -print0 \
        | sort -z \
        | cpio -0 -o -H newc --reproducible -R +0.+0 \
        | $compress
      ) > initramfs.img

      du -s --si "$src" initramfs.img

      install -p -m 444 -Dt $out initramfs.img
    '';

  init = writeScript "init.sh" ''
    #! /bin/sh -eu

    set -a
    PATH=/sw/bin:/bin
    TMPDIR=/tmp

    EDITOR=vi
    PAGER=less
    SHELL=/bin/sh

    TZ=:/run/localtime
    TZDIR=/sw/share/zoneinfo

    LANG=en_US.UTF-8
    LC_COLLATE=C
    LC_MESSAGES=C
    LOCALE_ARCHIVE=/sw/lib/locale/locale-archive

    PS1='${config.shellPrompt}'

    NIX_PATH=nixpkgs=${hostPackages.path}
    CURL_CA_BUNDLE=/sw/etc/ssl/certs/ca-bundle.crt
    set +a

    rescue() {
      echo "Entering rescue shell" >&2
      exec setsid -c sh -l
    }
    trap rescue EXIT QUIT TERM INT


    #
    # Helpers
    #

    mount_robind() {
      local what=''${1?What}
      mount "$what" "$what" -o bind
      mount "$what"         -o bind,remount,ro
    }

    #
    # Special filesystems
    #

    mount proc /proc -t proc
    mount sys /sys -t sysfs
    mount dev /dev -t devtmpfs
    mkdir /dev/pts
    mount devpts /dev/pts -t devpts
    mount tmp /tmp -t tmpfs
    mount run /run -t tmpfs

    mount /proc -o remount,hidepid=2,gid=26

    #
    # Kernel modules
    #

    echo /bin/modprobe > /proc/sys/kernel/modprobe
    . /load-modules

    #
    # Mount livefs
    #

    livefs=$(findfs LABEL=LINIX_LIVE)
    mount "$livefs" /mnt

    #
    # Copy all static assets into memory to allow the media to be removed
    #

    install -m 700 -d /run/live
    mount live /run/live -t tmpfs
    install -m 400 /mnt/nix-store.sqsh /run/live/nix-store.sqsh
    umount /mnt

    mount_robind /run/live

    #
    # Mount Nix store image
    #

    mount /run/live/nix-store.sqsh /nix/.store-ro
    mount store-overlay /nix/store -t overlay -o lowerdir=/nix/.store-ro,upperdir=/nix/.store-rw,workdir=/nix/.store-work

    chown root:nixbld /nix/store
    chmod 1775 /nix/store

    mount_robind /nix/store

    nix-store --load-db < /nix/store/.registration

    #
    # End of essential init
    #

    trap - EXIT QUIT TERM INT # lest we end up in rescue() on exit

    #
    # Boot misc.
    #

    if [ -r /dev/hwrng ] ; then
      head -c512 /dev/hwrng >/dev/urandom
    fi

    ${buildLib.sysctlCommandFromAttrs config.sysctls}

    dmesg -n 1

    echo UTC >/run/localtime

    ip link set lo up
    echo ${config.hostname} > /proc/sys/kernel/hostname

    cat >/run/resolv.conf <<EOF
    nameserver 127.0.0.1
    options edns0
    EOF

    mount_robind /etc

    mount_robind /var/empty

    mkdir -m 700 /run/keys
    mount keys /run/keys -t ramfs -o nodev,noexec,nosuid

    mkdir -m 700 /run/lock
    mount lock /run/lock -t tmpfs -o nodev,noexec,nosuid

    mkdir -m 700 /run/log
    mount log /run/log -t tmpfs -o nodev,noexec,nosuid

    chown live:live /home/live

    #
    # Console
    #

    echo "4 5 1 4" > /proc/sys/kernel/printk
    echo 0 > /sys/class/graphics/fbcon/cursor_blink || true

    kbd_mode -u
    gzip -dc /sw/share/keymaps/${config.consoleKeymap}.bmap.gz | loadkmap

    #
    # Dæmons
    #

    install -m 700 -d /run/runit

    mkdir -m 700 -p /run/supervise/lvmetad /run/supervise/udevd /run/supervise/nix-daemon  /run/supervise/unbound /run/supervise/socklog-unix /run/supervise/crond /run/supervise/ntpd
    mkdir -m 700 -p /run/supervise/lvmetad/log /run/supervise/udevd/log /run/supervise/nix-daemon/log  /run/supervise/unbound/log /run/supervise/socklog-unix/log /run/supervise/crond/log /run/supervise/ntpd/log
    install -m 750 -o log -g log -d /var/log/service/lvmetad
    install -m 750 -o log -g log -d /var/log/service/udevd
    install -m 750 -o log -g log -d /var/log/service/nix-daemon
    install -m 750 -o log -g log -d /var/log/service/unbound
    install -m 750 -o log -g log -d /var/log/service/crond
    install -m 750 -o log -g log -d /var/log/service/ntpd
    # XXX: ewww ...
    socklog-conf unix socklog-unix log /run/service /var/log/service/socklog-unix
    runsvdir -P /service ${buildLib.replicateChar 12 "."} &

    # udev-settle
    udevadm trigger --type=subsystems --action=add
    udevadm trigger --type=devices --action=add
    udevadm settle

    #
    # End of init
    #

    dmesg -c >/run/log/boot.log
    chmod 0400 /run/log/boot.log

    #
    # Main loop
    #

    SHELL=ash
    echo "The boot log is at /run/log/boot.log .." >&2
    echo "Entering main loop.  Call poweroff -f to exit"
    set +eu
    while : ; do setsid -c $SHELL -l ; done

    echo "Fin."
    poweroff -f
  '';

  systemPath = buildEnv {
    name = "system-path";
    paths = config.systemPackages;
    extraOutputsToInstall = [ "man" ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/include"
      "/lib"
      "/share"
    ];
    ignoreCollisions = true;
  };

  rootfs = runCommand "rootfs"
    { nativeBuildInputs = with buildPackages; [ kmod ];

      inherit (buildPackages)
        busyboxStatic
      ;

      inherit
        init
        systemPath
      ;

      modDirBase = config.linuxPackages.kernel;
      modDirVersion = config.linuxPackages.kernel.modDirVersion;
      inherit (config) modulesToLoad;
    }
    ''
      set -eu -o pipefail

      echo "Building root ..."

      mkdir $out && cd $out

      mkdir -m 755 dev
      mkdir -m 755 proc
      mkdir -m 755 sys
      mkdir -m 755 run
      mkdir -m 755 tmp

      mkdir -m 755 bin
      mkdir -m 755 lib
      mkdir -m 755 etc
      mkdir -m 755 var
      mkdir -m 755 var/empty
      mkdir -m 755 var/spool
      mkdir -m 700 root
      mkdir -m 700 home home/live
      mkdir -m 755 mnt

      mkdir -p -m 755 var/spool/cron/crontabs

      mkdir -p -m 700 var/lib/lvm/{archive,backup} var/cache/lvm
      mkdir -m 700 etc/lvm
      ln -s /var/lib/lvm/archive etc/lvm/archive
      ln -s /var/lib/lvm/backup etc/lvm/backup
      ln -s /var/cache/lvm etc/lvm/cache

      mkdir -m 755 nix nix/store nix/var nix/var/nix
      mkdir -m 700 nix/.store-rw nix/.store-ro nix/.store-work

      ln -s /run var/run
      ln -s /run/lock var/lock

      ln -s /proc/sys/kernel/hostname etc/hostname
      ln -s /proc/mounts etc/mtab
      ln -s /run/resolv.conf etc/resolv.conf
      ln -s /run/localtime etc/localtime

      mkdir -m 700 -p var/lib/dhcpcd
      ln -s /var/lib/dhcpcd/duid etc/dhcpcd.duid

      mkdir -m 700 etc/udev
      ln -s /sw/etc/udev/rules.d etc/udev/rules.d

      # Becomes valid once the Nix store is mounted
      ln -s "$systemPath" sw

      # Need a static busybox within the initramfs to bring up the Nix store
      echo "Installing static busybox binary ..."
      install -m 555 -D $busyboxStatic/bin/busybox lib/busybox
      lib/busybox --list | sort | while IFS= read -r app ; do
        ln -sf /lib/busybox bin/$app
      done

      echo "Installing /init ..."
      bash --posix -n "$init"
      install -m 555 "$init" init

      echo "Creating initramfs module tree ..."
      # Two things:
      #
      # 1. Generate a script that loads modulesToLoad and dependencies in
      #    load order, taking care to load each module only once
      # 2. Copy the entire module directory into initramfs (under /lib/modules)
      #
      # TODO: copy only minimum modules to initramfs; load the rest from
      #   store image.  Then we also need to configure a suitable modprobe.
      cp -a "$modDirBase/lib/modules" lib/modules

      declare -A insmodcmds
      # Note: munging occurs in parent shell so that changes to
      # variables can be used afterwards
      while IFS= read -r insmodcmd ; do
        [[ ''${insmodcmds["$insmodcmd"]+_} ]] && continue
        insmodcmds["$insmodcmd"]=
        sed 's,/nix/store/[^/]*,,' <<< "$insmodcmd"
      done \
        < <(modprobe -b -a -d "$modDirBase" -S "$modDirVersion" --show-depends $modulesToLoad) \
        > load-modules

      echo "Generating users and groups ..."
      nologin=/bin/nologin
      cat >etc/passwd <<EOF
      root::0:0:Super user:/root:/bin/sh
      nobody:x:99:99:Nobody:/var/empty:$nologin
      log:x:201:201:Log user:/var/empty:$nologin
      socklog-unix:x:202:202:Socklog user:/var/empty:$nologin
      unbound:x:401:401:Unbound daemon user:/var/empty:$nologin
      nixbld1:x:901:900:Nix build user 1:/var/empty:$nologin
      nixbld2:x:902:900:Nix build user 2:/var/empty:$nologin
      nixbld3:x:903:900:Nix build user 3:/var/empty:$nologin
      nixbld4:x:904:900:Nix build user 4:/var/empty:$nologin
      nixbld5:x:905:900:Nix build user 5:/var/empty:$nologin
      nixbld6:x:906:900:Nix build user 6:/var/empty:$nologin
      nixbld7:x:907:900:Nix build user 7:/var/empty:$nologin
      nixbld8:x:908:900:Nix build user 8:/var/empty:$nologin
      live::1000:1000:Live user:/home/live:/bin/sh
      EOF

      cat >etc/group <<EOF
      root:x:0:root
      tty:x:5:
      disk:x:6:root
      kmem:x:7:
      lp:x:8:
      dialout:x:9:
      wheel:x:10:root,live
      proc:x:26:root
      input:x:91:
      video:x:92:
      audio:x:93:
      tape:x:94:
      cdrom:x:95:
      nobody:x:99:nobody
      log:x:201:log
      socklog-unix:x:202:socklog-unix
      users:x:100:live
      unbound:x:401:unbound
      nixbld:x:900:nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8
      live:x:1000:live
      EOF

      echo "Generating hosts file ..."
      cat >etc/hosts <<EOF
      127.0.0.1 localhost.localdomain localhost
      127.0.1.1 ${config.hostname}

      ::1 ip6-localhost ip6-loopback
      fe00::0 ip6-localnet
      ff00::0 ip6-mcastprefix
      ff02::1 ip6-allnodes
      ff02::2 ip6-allrouters
      ff02::3 ip6-allhosts
      EOF

      echo "Generating periodic maintenance scripts ..."
      mkdir -m 700 -p etc/periodic
      cat >etc/periodic/15min <<EOF
      #! /bin/sh -e
      EOF
      chmod +x etc/periodic/15min
      cat >etc/periodic/hourly <<EOF
      #! /bin/sh -e
      EOF
      chmod +x etc/periodic/hourly
      cat >etc/periodic/daily <<EOF
      #! /bin/sh -e
      EOF
      chmod +x etc/periodic/daily
      cat >etc/periodic/weekly <<EOF
      #! /bin/sh -e
      EOF
      chmod +x etc/periodic/weekly

      echo "Generating root crontab ..."
      cat >var/spool/cron/crontabs/root <<EOF
      # min   hour    day     month   weekday command
      */15    *       *       *       *       run-parts /etc/periodic/15min
      0       *       *       *       *       run-parts /etc/periodic/hourly
      0       2       *       *       *       run-parts /etc/periodic/daily
      0       3       *       *       6       run-parts /etc/periodic/weekly
      0       5       1       *       *       run-parts /etc/periodic/monthly
      EOF

      echo "Generating files for runit-init ..."
      ln -s /run/runit etc/runit

      # See man:runsv(8)
      echo "Generating service definitions ..."
      mkdir -p service/lvmetad
      cat >service/lvmetad/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      install -m 700 -d /run/lvm
      exec lvmetad -f
      EOF
      chmod +x service/lvmetad/run
      ln -s /run/supervise/lvmetad service/lvmetad/supervise

      mkdir -p service/lvmetad/log
      cat >service/lvmetad/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main
      EOF
      chmod +x service/lvmetad/log/run
      ln -s /run/supervise/lvmetad/log service/lvmetad/log/supervise
      ln -s /var/log/service/lvmetad service/lvmetad/log/main

      mkdir -p service/udevd
      cat >service/udevd/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      exec udevd
      EOF
      chmod +x service/udevd/run
      ln -s /run/supervise/udevd service/udevd/supervise

      mkdir -p service/udevd/log
      cat >service/udevd/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main
      EOF
      chmod +x service/udevd/log/run
      ln -s /run/supervise/udevd/log service/udevd/log/supervise
      ln -s /var/log/service/udevd service/udevd/log/main

      mkdir -p service/crond
      cat >service/crond/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      exec crond -f -d 8 -c /var/spool/cron/crontabs
      EOF
      chmod +x service/crond/run
      ln -s /run/supervise/crond service/crond/supervise

      mkdir -p service/crond/log
      cat >service/crond/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main
      EOF
      chmod +x service/crond/log/run
      ln -s /run/supervise/crond/log service/crond/log/supervise
      ln -s /var/log/service/crond service/crond/log/main

      mkdir -p service/ntpd
      cat >service/ntpd/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      exec ntpd -n -p 0.pool.ntp.org -p 1.pool.ntp.org -p 2.pool.ntp.org -p 3.pool.ntp.org
      EOF
      chmod +x service/ntpd/run
      ln -s /run/supervise/ntpd service/ntpd/supervise

      mkdir -p service/ntpd/log
      cat >service/ntpd/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main
      EOF
      chmod +x service/ntpd/log/run
      ln -s /run/supervise/ntpd/log service/ntpd/log/supervise
      ln -s /var/log/service/ntpd service/ntpd/log/main

      mkdir -p service/nix-daemon
      cat >service/nix-daemon/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      exec nix-daemon
      EOF
      chmod +x service/nix-daemon/run
      ln -s /run/supervise/nix-daemon service/nix-daemon/supervise

      mkdir -p service/nix-daemon/log
      cat >service/nix-daemon/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main
      EOF
      chmod +x service/nix-daemon/log/run
      ln -s /run/supervise/nix-daemon/log service/nix-daemon/log/supervise
      ln -s /var/log/service/nix-daemon service/nix-daemon/log/main

      mkdir -p service/unbound
      cat >service/unbound/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      exec unbound -ddp
      EOF
      chmod +x service/unbound/run
      ln -s /run/supervise/unbound service/unbound/supervise

      mkdir -p service/unbound/log
      cat >service/unbound/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main
      EOF
      chmod +x service/unbound/log/run
      ln -s /run/supervise/unbound/log service/unbound/log/supervise
      ln -s /var/log/service/unbound service/unbound/log/main

      # Derived from `socklog-config unix`
      mkdir -p service/socklog-unix
      cat >service/socklog-unix/run <<EOF
      #! /bin/sh -eu
      exec 2>&1
      exec chpst -Usocklog-unix socklog unix /dev/log
      EOF
      chmod +x service/socklog-unix/run
      ln -s /run/supervise/socklog-unix service/socklog-unix/supervise

      mkdir -p service/socklog-unix/log
      cat >service/socklog-unix/log/run <<EOF
      #! /bin/sh -eu
      exec chpst -ulog svlogd -tt ./main/*
      EOF
      chmod +x service/socklog-unix/log/run
      ln -s /run/supervise/socklog-unix/log service/socklog-unix/log/supervise
      ln -s /var/log/service/socklog-unix service/socklog-unix/log/main
    '';

  build.livefs_vdi = runCommand "livefs-vdi"
    { nativeBuildInputs = with pkgs; [ qemuHeadless ];
      livefsImage = "${build.livefs}/live.fs";
    }
    ''
      echo "Converting raw image to VirtualDiskImage ..."
      qemu-img convert -f raw -O vdi "$livefsImage" live.vdi

      echo "Copying outputs ..."
      install -m 444 -Dt $out live.vdi
    '';

  build.livefs_qcow = runCommand "livefs-qcow"
    { nativeBuildInputs = with pkgs; [ qemuHeadless ];
      livefsImage = "${build.livefs}/live.fs";
    }
    ''
      echo "Converting raw image to qcow ..."
      qemu-img convert -c -f raw -O qcow2 "$livefsImage" live.qcow2

      echo "Copying outputs ..."
      install -m 444 -Dt $out live.qcow2
    '';

  # A compressed livefs for distribution (e.g., via http or bittorrent).
  #
  # Compression is performed primarily to gain built-in integrity
  # checking compared to serving a raw disk image.
  build.livefs_dist = runCommand "livefs-dist"
    { #nativeBuildInputs = with pkgs; [ xz ];
      livefsImage = "${build.livefs}/live.fs";
    }
    ''
      echo "Creating a compressed live.fs ..."
      #xz -v -C sha256 --threads=''${NIX_BUILD_CORES:-0} -9 -c "$livefsImage" > live.fs.xz
      gzip -1n -c "$livefsImage" > live.fs.gz

      echo "Copying outputs ..."
      install -m 444 -Dt $out live.fs.gz
    '';

  start-vm =
    let
      ovmfVars = "${hostPackages.edk2-ovmf}/share/ovmf/OVMF_VARS.fd";
      ovmfCode = "${hostPackages.edk2-ovmf}/share/ovmf/OVMF_CODE.fd";
      qemuProg = "${hostPackages.qemuHeadless}/bin/qemu-system-x86_64";
      qemuOpts = [
        "-net nic,netdev=net.0,model=virtio"
        "-netdev user,id=net.0"
        "-localtime"
        "-no-reboot"
        "-nographic"
        "-enable-kvm"
        "-cpu host"
        "-machine type=q35"
        "-accel kvm"
        "-smp $(nproc --all)"
        "-m 512M"

        "-object rng-random,filename=/dev/urandom,id=rng0"
        "-device virtio-rng-pci,rng=rng0"
        "-object cryptodev-backend-builtin,id=cryptodev0"
        "-device virtio-crypto-pci,id=crypto0,cryptodev=cryptodev0"

        "-drive media=disk,file=${build.livefs}/live.fs,readonly,format=raw,if=virtio"

        "-drive if=pflash,format=raw,readonly,file=${ovmfCode}"
        "-drive if=pflash,format=raw,file=$ovmfVars"

        "-drive media=disk,file=$diskFile,format=raw,if=virtio"
      ];
    in writeScript "start-vm.sh" ''
    #! /bin/sh -eu
    rundir=$PWD/run
    ovmfVars=$PWD/run/OVMF_VARS.fd
    diskFile=$PWD/run/hda.raw
    diskFileSize=10G
    mkdir -p "$rundir"; chattr +dC "$rundir"
    if [[ ! -e "$diskFile" ]] ; then
      truncate -s $diskFileSize "$diskFile"
    fi
    cp -uv --no-preserve=mode ${ovmfVars} $PWD/run/OVMF_VARS.fd
    exec ${qemuProg} ${toString qemuOpts} "$@"
  '';

  driver = testScript: pkgs.writeScript "driver" ''
    #! ${pkgs.expect}/bin/expect -f

    set timeout -1

    proc sendShellCommand {text} {
      expect "${config.shellPrompt}" {send "$text\r"}
    }

    spawn ${start-vm}

    expect "UEFI Interactive Shell"
    expect "Press" {send "\r"}

    ${testScript}

    sendShellCommand "halt -nf"
  '';

  tests.boot = driver ''
    sendShellCommand "cat /proc/sys/kernel/random/boot_id"
    sendShellCommand "uname -a"
    expect "Linux"
  '';
}