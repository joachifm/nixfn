{ nixpkgs ? import ./nixpkgs {} }:

let
  inherit (nixpkgs) lib pkgs;

  inherit (pkgs)
    buildEnv
    closureInfo
    runCommand
    writeScriptBin
  ;

  ifThenText = cond: text: if cond then text else "";

  singleton1 = obj: if builtins.isList obj then obj else [ obj ];

  ifThenList = cond: obj: if cond then singleton1 obj else [];

  runLocalCommand = name: args: runCommand name (args // {
    preferLocalBuild = true;
    allowSubstitutes = false;
  });

  busyboxStatic = pkgs.busybox.override {
    enableStatic = true;
  };

  qemuPackage = pkgs.qemu_kvm;

  qemuArch = "x86_64";

  glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [ "en_US.UTF-8/UTF-8" ];
  };

  tzctl = writeScriptBin "tzctl" ''
    #! /bin/sh -eu
    tzpath=/sw/share/zoneinfo/$1
    if ! [ -f "$tzpath" ] ; then
      echo "invalid timezone: $1" >&2
      exit 2
    fi
    ln -nsf $tzpath /run/localtime.tmp
    mv -f /run/localtime.tmp /run/localtime
  '';

  vmShares = [
    { hostPath = "/nix/store";
      guestPath = "/nix/.store-host";
      mountTag = "host-nix-store";
      readonly = true;
    }
    { hostPath = "/tmp/xchg";
      guestPath = "/tmp/xchg";
      mountTag = "host-xchg";
      readonly = false;
    }
  ];

  nVmShares = builtins.length vmShares;

  guestMountVmShare = cfg:
    let
      fsOpts = [
        "trans=virtio"
        ("cache=" + (if cfg.readonly then "loose" else "none"))
        "version=9p2000.L"
      ];
    in
    "mount ${cfg.mountTag} ${cfg.guestPath} -t 9p -o " +
    lib.concatStringsSep "," fsOpts;

  createHostVmShare = cfg: "install -d ${cfg.hostPath}";

  vmShareQemuFlag = i: cfg:
      "-virtfs local,id=fsdev_${toString i},path=${cfg.hostPath},security_model=mapped"
    + (ifThenText cfg.readonly ",readonly")
    + ",mount_tag=${cfg.mountTag}"
    + " "
    + "-device virtio-9p-pci,id=fs${toString i},fsdev=fsdev_${toString i},mount_tag=${cfg.mountTag}";
in
rec {

  mutableTimeZone = true;

  timeZone = "UTC";

  project.meta = { version = "2018.12-rc2"; };

  storeContents = with pkgs; [
    stdenv
  ];

  basePackages = with pkgs; [
    cacert
    glibcLocales
    nix
    tzdata.out  # .bin is default
  ] ++ ifThenList mutableTimeZone tzctl;

  modulesToLoad = [
    "loop"
    "overlay"
    "squashfs"
    "vfat"
      "nls_iso8859_1"
      "nls_cp437"
    "9p"
    "9pnet"

    "virtio"
    "virtio-blk"
    "virtio-pci"
    "virtio-net"
    "9pnet_virtio"

    "dm_mod"
  ];

  globalPackages = with pkgs; [
    # boot
    efibootmgr

    # fs
    btrfsProgs
    e2fsprogs
    dosfstools
    mtools
    xfsprogs

    # block
    cryptsetup
    gptfdisk
    lvm2

    # editor
    mg

    # net
    dropbear
    rfkill
    rsync
    wpa_supplicant

    # http/www
    lynx

    # crypto
    gnupg
    openssl_1_1

    # debug
    strace

    # rescue
    ddrescue
  ];

  linuxPackages = pkgs.linuxPackages_latest;

  kernelPackage = linuxPackages.kernel;

  linuxEfiStub = "${kernelPackage}/bzImage";

  packageEnv = buildEnv {
    name = "packages-env";
    paths =
         basePackages
      ++ globalPackages;
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/share"
    ];
  };

  closure = closureInfo {
    rootPaths = [ packageEnv ] ++ storeContents;
  };

  moduleTree = runLocalCommand "modules-${kernelPackage.version}"
    { inherit modulesToLoad;
      inherit (kernelPackage) modDirVersion;
      modDirPrefix = "${kernelPackage}";
      nativeBuildInputs = [ pkgs.kmod ];
      outputs = [ "out" "bin" ];
    }
    ''
    mkdir -p $bin $out

    declare -A seen  # avoid emitting duplicate insmod commands
    while read -r insmod ; do
      if [[ ''${seen["$insmod"]+_} ]] ; then
        continue
      fi
      seen["$insmod"]=

      # munge the original insmod command
      cmdparts=($insmod) # expect "insmod <path_to_mod>[ <param1>...]"
      modconf=''${cmdparts[@]:2}

      # rewrite module src path to dest path
      srcmod=''${cmdparts[1]}
      dstmod=$(sed "s,${builtins.storeDir}/[^/]*,$out," <<< "$srcmod")

      # copy src to dest
      install -D $srcmod $dstmod -m 444

      # reconstitute insmod command
      insmod2="insmod $dstmod ''${modconf[@]}"
      echo $insmod2 >> insmod
    done < <(modprobe \
      --dirname=$modDirPrefix \
      --set-version=$modDirVersion \
      --show-depends \
      --all \
      $modulesToLoad)

    # Regenerate modules.dep and friends
    depmod -w -b $out -F $modDirPrefix/System.map $modDirVersion

    oldSize=$(du -sb $modDirPrefix | cut -f1)
    newSize=$(du -sb $out          | cut -f1)
    diffSize=$(((newSize-oldSize) / 1000 / 1000))
    echo "$diffSize MB" >&2

    install -Dt $bin insmod
    '';

  storeImage = runLocalCommand "nix-store-sqsh"
    { nativeBuildInputs = [ pkgs.squashfsTools ];
      inherit closure;
    }
    ''
    mkdir root
    xargs -P$NIX_BUILD_CORES -rn1 \
      cp --sparse=always --reflink=auto -R --preserve=mode,ownership,timestamps,links -t root/ \
      < $closure/store-paths
    cp $closure/registration root/.registration

    cat >exclude-patterns <<'EOF'
    *.la
    */share/locale
    EOF

    mksquashfs root nix-store.sqsh \
      -progress \
      -comp gzip -Xcompression-level 1 \
      -no-exports \
      -no-xattrs \
      -no-duplicates \
      -no-fragments \
      -force-uid 0 \
      -force-gid 0 \
      -exit-on-error \
      -no-recovery \
      -processors $NIX_BUILD_CORES \
      -wildcards -ef exclude-patterns

    install -Dt $out nix-store.sqsh -m 444
    '';

  initramfs = runLocalCommand "initramfs"
    { inherit busyboxStatic;
      inherit packageEnv;
      inherit moduleTree;

      nativeBuildInputs = with pkgs; [
        cpio
        pigz
      ];
    }
    ''
    mkdir root && cd root

    # Initial root hierarchy
    install -d bin  -m 0755
    install -d lib  -m 0755
    install -d root -m 0700
    install -d dev  -m 0755
    install -d proc -m 0755
    install -d sys  -m 0755
    install -d run  -m 0755
    install -d tmp  -m 1777
    install -d var
    install -d var/cache
    install -d var/empty
    install -d var/lib
    install -d var/log

    # Nix scaffolding
    install -d nix
    install -d nix/store
    install -d nix/.ro
    install -d nix/.rw
    install -d nix/.wd
    install -d nix/var nix/var/log/nix nix/var/nix

    # Legacy /var
    ln -s /run      var/run
    ln -s /run/lock var/lock

    # LVM2
    install -d var/cache/lvm -m 700
    install -d etc/lvm       -m 700
    ln -s /var/cache/lvm etc/lvm/cache


    # Install static tools to initramfs root
    install $busyboxStatic/bin/busybox lib/busybox
    $busyboxStatic/bin/busybox --list | while read -r appname ; do
      ln lib/busybox bin/$appname
    done


    # Becomes valid once the Nix store is mounted
    ln -s $packageEnv sw


    install -d lib/
    cp -R $moduleTree/lib/modules/ lib/


    # Generate static sysconfig
    install -d etc
    cat >etc/passwd <<EOF
    root:x:0:0::/root:/bin/sh
    nobody:x:99:99::/var/empty:/bin/false
    EOF

    cat >etc/group <<EOF
    root:x:0:root
    disk:x:3:
    tty:x:5:
    wheel:x:10:
    proc:x:21:
    nobody:x:99:nobody
    users:x:100:
    nixbld:x:990:
    EOF

    ln -s /proc/self/mounts etc/mtab

    cat >etc/hosts <<EOF
    127.0.0.1 localhost.localdomain localhost
    127.0.1.1 livefs

    ::1 ip6-localhost ip6-loopback
    fe00::0 ip6-localnet
    ff00::0 ip6-mcastprefix
    ff02::1 ip6-allnodes
    ff02::2 ip6-allrouters
    ff02::3 ip6-allhosts
    EOF


    ${let
        target = if mutableTimeZone then "/run/localtime" else "/sw/share/zoneinfo/${timeZone}";
      in "ln -s ${target} etc/localtime"}


    # Generate the shutdown script
    cat >shutdown <<EOF
    #! /bin/sh
    killall5 -TERM
    sleep 0.2
    killall5 -KILL
    mount / -o remount,ro
    sync
    poweroff -nf
    # shutdown script ends here
    EOF

    $shell -n shutdown
    chmod +x shutdown


    # Generate the initramfs init script
    cat >init <<EOF
    #! /bin/sh

    rescue() {
      echo "Entering rescue shell!" >&2
      exec setsid -c sh -l
    }
    trap rescue EXIT
    set -eu

    set -a
    PATH=/sw/bin:/bin
    SHELL=/bin/sh
    LOCALE_ARCHIVE=/sw/lib/locale/locale-archive
    LANG=en_US.UTF-8
    LC_MESSAGES=C
    LC_COLLATE=C
    TZDIR=/sw/share/zoneinfo
    TZ=:${if mutableTimeZone then "/run/localtime" else timeZone}
    SSL_CERT_FILE=/sw/etc/ssl/certs/ca-bundle.crt
    CURL_CA_BUNDLE=/sw/etc/ssl/certs/ca-bundle.crt
    set +a


    mount proc   /proc    -t proc     -o nodev,noexec,nosuid
    mount dev    /dev     -t devtmpfs -o noexec,nosuid
    mkdir /dev/pts
    mount devpts /dev/pts -t devpts   -o noexec,nosuid
    mount sys    /sys     -t sysfs    -o nodev,noexec,nosuid
    mount tmp    /tmp     -t tmpfs    -o size=50%,nodev,nosuid
    mount run    /run     -t tmpfs    -o size=10%,nodev,noexec,nosuid
    chmod 1777 /tmp

    mkdir /run/log
    chmod 0750 /run/log

    mkdir /run/lock

    ln -nsf /dev/urandom /dev/random


    ${lib.concatStringsSep "\n" (map (modName: "modprobe ${modName}") modulesToLoad)}


    livefsdev=\$(findfs LABEL=LIVEFS)
    livefsmnt=/run/mnt/livefs
    mkdir -p "\$livefsmnt" -m 700
    mount "\$livefsdev" "\$livefsmnt" -o ro

    mount "\$livefsmnt/nix-store.sqsh" /nix/.ro
    mount store-overlay  /nix/store -t overlay \
      -o lowerdir=/nix/.ro,upperdir=/nix/.rw,workdir=/nix/.wd


    chown 0:990 /nix/store
    chmod 1775  /nix/store

    mount /nix/store /nix/store -o bind
    mount /nix/store            -o remount,bind,ro


    hash -r


    nix-store --load-db < /nix/store/.registration
    nix-store --register-validity --hash-given < /nix/store/.registration


    install -d /nix/.store-host
    install -d /tmp/xchg
    ${lib.concatStringsSep "\n"
      (map guestMountVmShare vmShares)}


    mount /var/empty /var/empty -o bind
    mount /var/empty            -o remount,bind,ro

    ln -nsf /proc/self/fd/0 /dev/stdin
    ln -nsf /proc/self/fd/1 /dev/stdout
    ln -nsf /proc/self/fd/2 /dev/stderr
    ${ifThenText mutableTimeZone "tzctl UTC"}
    hwclock --systz
    ip link set lo up
    dmesg -c > /run/log/dmesg.log


    vgscan --mknodes


    trap - EXIT
    set +eu
    while : ; do
        sh -l
        ret=$?
        sleep 0.1
    done

    # init ends here
    EOF

    $shell -n init
    chmod +x init

    find . -mindepth 1 -exec touch -hd@1 '{}' +

    find . -mindepth 1 -print0 \
      | sort -z \
      | cpio --null -o -H newc --reproducible -R +0:+0 \
      | pigz --no-time --processes $NIX_BUILD_CORES --best \
      > ../initramfs.img

    cd ..
    install -Dt $out initramfs.img -m 444
    '';

    livefs = runLocalCommand "livefs-${project.meta.version}"
      { nativeBuildInputs = with pkgs; [ dosfstools gptfdisk mtools ];
        inherit initramfs storeImage linuxEfiStub;
        meta = { inherit (project.meta) version; };
      }
      ''
      mkdir esproot && cd esproot

      install $initramfs/initramfs.img   initramfs.img  -m 444
      install $linuxEfiStub              linux.efi      -m 444
      install $storeImage/nix-store.sqsh nix-store.sqsh -m 444

      cat >startup.nsh <<EOF
      linux.efi initrd=\initramfs.img
      EOF

      cd ..


      # Note: imageSize is diskSize-2 to leave room for GPT partition table
      # at the beginning of the disk and at the end.
      diskSize=512MiB
      imageSize=510MiB

      echo "Allocating space for root.fs"
      truncate -s $imageSize root.fs

      echo "Creating root.fs filesystem"
      mkfs.fat --invariant -F 32 -n LIVEFS root.fs

      echo "Populating root.fs"
      find esproot -mindepth 1 -exec touch -hd '1980-01-01 01:01' '{}' +
      MTOOLS_SKIP_CHECK=1 \
      mcopy -i root.fs -bspQmv esproot"/"* ::

      echo "Allocating space for live.fs"
      truncate -s $diskSize live.fs

      echo "Partitioning disk image"
      sgdisk -Zo live.fs \
        -U bf1ab1d8-c3f9-427c-928f-5f14b7b58786 \
        \
        -n 0:0:0 \
        -t 0:ef00 \
        -u 0:6259e6f0-13be-4b9e-a30f-d60b9439b4de \
        \
        -vp

      echo "Populating disk image"
      # Note: need to skip first 1MB to avoid clobbering GPT
      # Note: need conv=notrunc to avoid clobbering GPT
      start=2048 # sectors
      obs=$((start * 512)) # sector count \times bytes-per-sector = 1MB
      dd if=root.fs of=live.fs obs=$obs seek=1 conv=sparse,notrunc

      echo "Checking disk image"
      sgdisk live.fs -evp

      echo "Copying outputs"
      install -Dt $out live.fs -m 444
      '';

    runVm = writeScriptBin "run-vm" ''
      #! ${pkgs.runtimeShell} -eu

      rundir=$PWD/run
      readonly rundir

      mkdir -p $rundir
      chattr +dC $rundir
      if ! [[ -r $rundir/live.fs ]] ; then
         cp --no-preserve=mode --sparse=always ${livefs}/live.fs $rundir/live.fs
      fi

      install -d /tmp/xchg

      exec ${qemuPackage}/bin/qemu-system-${qemuArch} \
        -enable-kvm \
        -machine q35,accel=kvm \
        -device intel-iommu \
        -cpu host \
        -m 765M \
        -nographic \
        -no-reboot \
        -drive file=$rundir/live.fs,format=raw,if=virtio \
        ${lib.concatStringsSep " "
          (lib.genList (i: vmShareQemuFlag i (lib.elemAt vmShares i))
                       nVmShares)} \
        -append 'quiet oops=panic apparmor=0 console=ttyS0' \
        -kernel '${linuxEfiStub}' \
        -initrd '${initramfs}/initramfs.img' \
        "$@"
    '';
}
