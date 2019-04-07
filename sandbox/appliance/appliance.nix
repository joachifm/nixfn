/**
 * @param buildPackages is the package set used during the build
 *
 * @param hostPackages is the package set for artefacts that execute
 *    on the vm host machine
 *
 * @param targetPackages is the package set for artefacts that execute
 *    within the vm guest
 */
{ buildPackages ? import <nixpkgs>{}
, hostPackages ? buildPackages
, targetPackages ? hostPackages
}:

/**
 * @param vmDisk is a set of disk images attached to the virtual machine
 *    instance.  The script creates empty images if they do not exist.
 *
 *    type vmDisk = {
 *      name : string   optional name, used e.g., for naming the backing file
 *      size : string   size of disk, in format understood by man:truncate(1)
 *    }
 *
 * @param vmShares is a set of directories shared with
 *    the host.  The script fails if any of the named
 *    host-side directories do not exist.
 *
 *    type vmShare = {
 *      hostPath : path     host-side directory
 *      guestPath : path    guest-side directory
 *      tag : string        mount_tag parameter value
 *      readonly : bool     whether share is readonly on the guest side
 *      preMount : string   command executed immediately before mount
 *      postMount : string  command executed immediately after mount
 *    }
 *
 * @param modulesToLoad is a set of additional kernel
 *    modules to load within the guest.
 */

{ vmMemSize ? "64M"
, vmCpuArch ? "x86_64"
, vmNumCpu ? 2
, vmDisks ? [ ]
, vmShares ? [ ]
, vmKeymap ? "no-latin1"
, timeZone ? "UTC"
, hostname ? "localhost"
, modulesToLoad ? [ ]
, pkgsFn ? (pkgs: [])
, preCommand ? ""
, command
}:

let
  inherit (buildPackages)
    lib
    buildEnv
    runCommand
    writeScript
  ;

  inherit (hostPackages)
    runtimeShell
  ;

  busyboxStatic = targetPackages.busybox.override {
    enableStatic = true;
  };

  glibcLocales = targetPackages.glibcLocales.override {
    allLocales = false;
    locales = [ "en_US.UTF-8/UTF-8" ];
  };
in

with lib;

let
  basePackages = with targetPackages; [
    cacert
    glibcLocales
    tzdata.out  # .bin is default
  ];

  allPackages = basePackages ++ (pkgsFn targetPackages);

  linuxPackages = targetPackages.linuxPackages_latest;

  packagesEnv = buildEnv {
    name = "system-path";
    paths = allPackages;
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/share"
    ];
    ignoreCollisions = true;
  };

  nDisks = lib.length vmDisks;

  nShares = lib.length allShares;

  baseKernelModules = [
    "overlay"
    "virtio-pci"
    "virtio-rng"
  ] ++ lib.optionals nShares [
    "9p"
    "9pnet"
    "9pnet-virtio"
  ];

  cacertPath = "/sw/etc/ssl/certs/ca-bundle.crt";

  allKernelModules = baseKernelModules ++ modulesToLoad;

  defaultShares = [
    { hostPath = "/tmp/xchg";
      guestPath = "/xchg";
      tag = "xchg";
    }

    { hostPath = "/nix/store";
      guestPath = "/nix/.store-ro";
      tag = "host-store";
      readonly = true;
    }
  ];

  allShares = defaultShares ++ vmShares;
in

let
  /**
   * Construct derivation that produces a path comprising:
   * - a reduced module tree, the specified modules and dependencies
   * - a straight-line script to load modules and apply options
   * - updated module dependency files
   */
  buildModuleTree =
    { modulesToLoad
    , kernelPackage ? linuxPackages.kernel
    , storeDir ? builtins.storeDir
    }:
    runCommand "linux-modules-${kernelPackage.version}"
    { nativeBuildInputs = with buildPackages; [ kmod ];
      inherit kernelPackage;
      inherit (kernelPackage) modDirVersion;
      modDirPrefix = kernelPackage;
      inherit storeDir;
      inherit modulesToLoad;
      meta.broken = !(builtins.isList modulesToLoad && modulesToLoad != []);

      preferLocalBuild = true;
      allowSubstitutes = false;
    }
    ''
    cat >modprobe.conf <<EOF
    EOF
    modprobeConf=$PWD/modprobe.conf

    cat >depmod.conf <<EOF
    EOF
    depmodConf=$PWD/depmod.conf

    declare -A seen  # prevent duplicate insmod commands while preserving order
    while read -r insmod ; do
      if [[ ''${seen["$insmod"]+_} ]] ; then  # skip seen
        continue
      fi
      seen["$insmod"]=  # mark as seen

      # munge original insmod command
      parts=($insmod)  # expects insmod <path_to_module> [<option>...]
      modSrc=''${parts[1]}
      modOpt=''${parts[@]:2}

      # strip store path, returning e.g., lib/modules/../foo.ko
      arg=\''${LINUX_MODULE_PREFIX:-$out}
      modPath=$(sed "s,$storeDir/[^/]*/,," <<< "$modSrc")
      modDst=$out/$modPath

      # copy module to dest
      install -D "$modSrc" "$modDst" -m 444

      # emit insmod command
      echo insmod $modPath ''${modOpt[@]}
    done < <(modprobe \
        --config "$modprobeConf" \
        --use-blacklist \
        --dirname "$modDirPrefix" \
        --set-version "$modDirVersion" \
        --show-depends \
        --all \
        $modulesToLoad) \
      > load-modules

    # regenerate modules.dep and friends
    depmod \
      -w \
      -C "$depmodConf" \
      -a \
      -b "$out" \
      -F "$kernelPackage/System.map" \
      "$modDirVersion"

    # verify that we generated a syntactically valid script
    [[ -s load-modules ]] || echo "empty load-modules"
    $shell --posix -n load-modules
    # TODO: verify that all modules are included
    #comm --nocheck-order -23 <(tr ' ' '\n' <<< $modulesToLoad) load-modules

    install -Dt $out load-modules

    # calculate space savings
    oldSize=$(du -sb $modDirPrefix | cut -f1)
    newSize=$(du -sb $out          | cut -f1)
    diffSize=$(((newSize-oldSize) / 1000 / 1000))
    echo "$diffSize MB" >&2
    '';
in

rec {
  moduleTree = buildModuleTree {
    modulesToLoad = allKernelModules;
  };


  /**
   * The applicance init
   */
  init = writeScript "init" ''
    #! /bin/sh -e
    set -a
    PATH=/sw/bin:/bin
    SHELL=/bin/sh
    TMPDIR=/tmp

    LOCALE_ARCHIVE=/sw/lib/locale/locale-archive
    LANG=en_US.UTF-8
    LC_MESSAGES=C
    LC_COLLATE=C

    TZDIR=/sw/share/zoneinfo
    TZ=:/sw/share/zoneinfo/${timeZone}

    SSL_CERT_FILE=${cacertPath}
    CURL_CA_BUNDLE=${cacertPath}

    NIX_PATH=nixpkgs=${targetPackages.path}
    NIX_STORE=${builtins.storeDir}
    NIX_BUILD_TOP=$TMPDIR
    set +a

    . ./load-modules

    mount proc /proc -t proc
    mount dev /dev -t devtmpfs
    mount sys /sys -t sysfs
    mkdir -m 755 /dev/pts
    mount devpts /dev/pts -t devpts
    mount run /run -t tmpfs
    mount tmp /tmp -t tmpfs
    chmod 1777 /tmp


    install -d /run/log -o 0 -g 0 -m 750


    ln -nsf /dev/urandom /dev/random


    ln -nsf /proc/self/fd/0 /dev/stdin
    ln -nsf /proc/self/fd/1 /dev/stdout
    ln -nsf /proc/self/fd/2 /dev/stderr


    for opt in $(< /proc/cmdline) ; do
      case "$opt" in
        (x.seed=*)
          set -- $(IFS==; echo $opt) ; seed=$2
          echo -n "$seed" > /dev/urandom
        ;;
        (x.out=*)
          set -- $(IFS==; echo $opt) ; out=$2
        ;;
      esac
    done


    mount_robind() {
      local what=''${1?What}
      local where=''${2:-$what}
      mount "$what" "$where" -o bind
      mount "$where"         -o remount,bind,ro
    }


    ${guestMountSharesCommand}


    mount none /nix/.store-rw -t tmpfs
    install -d /nix/.store-rw/upper
    install -d /nix/.store-rw/work

    mount store-overlay /nix/store -t overlay \
      -o lowerdir=/nix/.store-ro,upperdir=/nix/.store-rw/upper,workdir=/nix/.store-rw/work


    chmod 1775 /nix/store
    chown 0:990 /nix/store
    mount_robind /nix/store


    ip link set lo up
    echo ${hostname} > /proc/sys/kernel/hostname


    mount_robind /etc
    mount_robind /var/empty


    dmesg -c > /xchg/boot.log
    cat /proc/sys/kernel/random/boot_id > /xchg/boot_id

    ${preCommand}

    set +eu
    (
    set -eux
    ${command}
    ) | tee /xchg/command.log
    res=$?
    set -eu

    echo $res > /xchg/command-return-code
    dmesg > /xchg/dmesg.log

    if [ -e pause-after-command ] ; then
      (set +eu; setsid -c sh -l; exit 0)
    fi

    set +eu
    #! /bin/sh
    killall5 -TERM
    sleep 0.1
    killall5 -KILL
    mount / -o remount,ro
    sync
    poweroff -nf
  '';


  /**
   * The applicance rootfs
   */
  root = runCommand "root"
    { inherit (buildPackages) busybox;
      inherit
        init
        moduleTree
        packagesEnv
      ;
      inherit busyboxStatic;
    }
    ''
    mkdir $out && cd $out

    # Basic hierarchy
    mkdir -m 755 bin dev etc lib mnt proc run sys tmp
    mkdir -m 700 root
    mkdir -m 755 var var/cache var/empty var/lib var/log var/tmp

    # Legacy /var
    ln -s /run var/run
    ln -s /run/lock var/lock

    # Nix
    mkdir -m 755 nix nix/store
    mkdir -m 700 nix/.store-ro nix/.store-rw

    # Host exchange
    mkdir -m 755 xchg


    ln -s /proc/mounts etc/mtab
    ln -s /proc/sys/kernel/hostname etc/hostname
    ln -s /sw/share/zoneinfo/$timeZone etc/localtime


    cat >etc/passwd <<EOF
    root::0:0:/root:Super user:/bin/sh
    user::1000:1000:/home/user:User:/bin/sh
    nobody:x:65534:65534:/var/empty:Nobody:/bin/false
    EOF
    for i in $(seq 8) ; do
      echo nixbld$i:x:99$i:990:/var/empty:Nix build user $i:/bin/false
    done >>etc/passwd

    cat >etc/group <<EOF
    root:x:0:root
    adm:x:1:
    log:x:2:
    disk:x:3:
    audio:x:4:
    tty:x:5:
    video:x:6:
    kmem:x:7:
    lp:x:8:
    tape:x:9:
    cdrom:x:10:
    kmem:x:11:
    dialout:x:12:
    input:x:13:
    render:x:14:
    kvm:x:15:
    proc:x:26:
    wheel:x:99:root
    users:x:100:
    user:x:1000:user
    nixbld:x:990:nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8
    nobody:x:65534:nobody
    EOF

    cat >etc/hosts <<EOF
    127.0.0.1 localhost.localdomain localhost
    127.0.1.1 ${hostname}

    ::1 ip6-localhost ip6-loopback
    fe00::0 ip6-localnet
    ff00::0 ip6-mcastprefix
    ff02::1 ip6-allnodes
    ff02::2 ip6-allrouters
    ff02::3 ip6-allhosts
    EOF


    # Install static userland
    cp -L $busyboxStatic/bin/busybox lib/busybox
    $busybox/bin/busybox --list | while read -r app ; do
      ln lib/busybox bin/$app
    done

    # Compatibility with /usr/bin/env shebangs
    mkdir -m 755 usr usr/bin
    ln lib/busybox usr/bin/env


    # Becomes valid once Nix store is mounted
    ln -s "$packagesEnv" sw


    cp -R $moduleTree/lib/modules lib/
    install $moduleTree/load-modules load-modules -m 555


    install $init init -m 555
    $shell --posix -n init
  '';


  /**
   * The applicance initramfs image
   */
  initramfs = runCommand "initramfs"
    { nativeBuildInputs = with buildPackages; [ cpio ];
      fileName = "initramfs.img";
      inherit root;
    }
    ''
    find "$root" -mindepth 1 -printf '%P\0' \
      | LC_ALL=C sort -z \
      | cpio -D "$root" -0 -o -H newc --reproducible -R +0:+0 \
      > $NIX_BUILD_TOP/$fileName
    install -Dt $out $NIX_BUILD_TOP/$fileName -m 444
    '';


  createVirtDisks = concatStringsSep "" (zipListsWith (n: cfg:
    let name = cfg.name or "disk${toString n}"; in
  ''
    install -d "$rundir" -m 700
    chattr +dC "$rundir"
    if ! [ -e "$rundir/${name}.raw" ] ; then
      truncate -s ${toString cfg.size} "$rundir/${name}.raw"
    fi
  '') (genList (x: x) nDisks) vmDisks);

  virtDiskOpts = concatLists (zipListsWith (n: cfg:
    let name = cfg.name or "disk${toString n}"; in
    [ "-drive media=disk,if=virtio,cache=unsafe,file=$rundir/${name}.raw,format=raw" ])
    (genList (x: x) nDisks) vmDisks);

  guestMountSharesCommand = concatMapStringsSep "" (cfg: ''
    ${cfg.preMount or ""}
    mount ${cfg.tag} ${cfg.guestPath or cfg.hostPath} -t 9p -o trans=virtio,version=9p2000.L,cache=loose
    ${cfg.postMount or ""}
  '') allShares;

  createHostShares = concatMapStringsSep "" (cfg: ''
    install -d '${cfg.hostPath}' -m 700
  '') allShares;

  virtfsOpts1 = n: cfg: "-virtfs " + concatStringsSep "," (
    [ "local"
      "id=fsdev${toString n}"  # matches fsdev= in virtfsDeviceFlags
      "path=${cfg.hostPath}"
      "security_model=none"
      "mount_tag=${cfg.tag}"
    ] ++ lib.optional (cfg.readonly or false) "readonly");

  virtfsOpts = zipListsWith virtfsOpts1
    (genList (x: x) nShares)
    allShares;

  virtfsDeviceFlags = i: cfg: "-device " + concatStringsSep "," (
    [ "virtio-9p-pci"
      "id=fs${toString i}"
      "fsdev=fsdev${toString i}"  # matches id= in virtfsOpts
      "mount_tag=${cfg.tag}"
    ]);

  vmSharesQemuFlags = concatStringsSep " " (
    (lib.genList
      (i: let cfg = lib.elemAt vmShares i; in
      virtfsFlags i cfg + " " + virtfsDeviceFlags i cfg)
      (lib.length nShares));

  runner =
    let
      bzImage = "${linuxPackages.kernel}/bzImage";

      initrd = "${initramfs}/${initramfs.fileName}";

      kernelParams = toString [
        "apparmor=0"
        "audit=0"
        "console=ttyS0"
        "elevator=noop"
        "oops=panic"
        "panic=-1"
        "quiet"
        "cryptomgr.notests"
      ];

      qemuArch = vmCpuArch;

      qemuArchOpts = {
        "x86_64" = [ "-machine q35,accel=kvm" ];
      };

      qemuPackage = hostPackages.qemu;

      qemuProg = "${qemuPackage}/bin/qemu-system-${qemuArch}";

      qemuOpts = [
        "-no-reboot"
        "-nographic"
        "-k ${vmKeymap}"

        "-enable-kvm"
        "-cpu host"
        "-device intel-iommu"

        "-smp ${toString vmNumCpu}"
        "-m ${vmMemSize}"

        "-net none"
      ]
      ++ [
        # Map urandom on  host to random on guest (verify usage by lsof on host)
        #
        # Note that if the host supports e.g., RDRAND it should not be
        # necessary to seed the guest CSPRNG.
        "-object rng-random,filename=/dev/urandom,id=rng0"
        "-device virtio-rng-pci,rng=rng0"

        # Register virtio crypto device
        "-object cryptodev-backend-builtin,id=cryptodev0"
        "-device virtio-crypto-pci,id=crypto0,cryptodev=cryptodev0"
      ]
      ++ qemuArchOpts."${vmCpuArch}"
      ++ virtfsOpts
      ++ virtDiskOpts
      ++ [
        "-kernel '${bzImage}'"
        "-initrd '${initrd}'"
        ''-append "${toString kernelParams} x.seed=$seed"''
      ];
    in
    writeScript "run-appliance" ''
      #! ${hostPackages.runtimeShell} -eu
      rundir=$PWD/run
      seed=$(tr -dc '[:xdigit:]' < /dev/urandom | head -c16)
      ${createVirtDisks}
      exec ${qemuProg} ${toString qemuOpts} "''${@}"
    '';
}
