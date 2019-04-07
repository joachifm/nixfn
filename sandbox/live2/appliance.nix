{ nixpkgs ? import ./nixpkgs {} }:

let
  inherit (nixpkgs) lib pkgs;

  inherit (pkgs)
    buildEnv
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

  vmShares = [
    { hostPath = "/nix/store";
      guestPath = "/nix/store";
      tag = "host-nix-store";
      readonly = false;
    }
  ];

  guestMountVmShare = cfg:
    "mount ${cfg.tag} ${cfg.guestPath} -t 9p -o trans=virtio,version=9p2000.L";

  createHostVmShare = cfg: "install -d ${cfg.hostPath}";

  virtfsFlags = i: cfg: "-virtfs " + lib.concatStringsSep "," (
    [ "local"
      "id=fsdev${toString i}"  # matches fsdev= in the device spec below
      "path=${cfg.hostPath}"
      "security_model=none"
      "mount_tag=${cfg.tag}"
    ] ++ ifThenList cfg.readonly "readonly");

  virtfsDeviceFlags = i: cfg: "-device " + lib.concatStringsSep "," (
    [ "virtio-9p-pci"
      "id=fs${toString i}"
      "fsdev=fsdev${toString i}"
      "mount_tag=${cfg.tag}"
    ]);

  vmSharesQemuFlags = lib.concatStringsSep " " (
    (lib.genList
      (i: let cfg = lib.elemAt vmShares i; in
      virtfsFlags i cfg + " " + virtfsDeviceFlags i cfg)
      (lib.length vmShares)));
in

{ timeZone ? "Europe/Oslo"
, packages ? (ps: [])
, modulesToLoad ? []
, hostname ? "localhost"
, vmMemSize ? "512M"
, vmNumCpus ? 1
}:

let
  basePackages = with pkgs; [
    cacert
    glibcLocales
    tzdata.out  # .bin is default
  ];

  baseModulesToLoad = [
    "9p"
    "9pnet_virtio"
    "loop"
    "virtio"
    "virtio_blk"
    "virtio_net"
    "virtio_pci"
    "virtio_rng"
  ];

  allPackages = basePackages ++ (packages pkgs);

  allModulesToLoad = baseModulesToLoad ++ modulesToLoad;

  linuxPackages = pkgs.linuxPackages_latest;

  kernelPackage = linuxPackages.kernel;

  linuxEfiStub = "${kernelPackage}/bzImage";

  packageEnv = buildEnv {
    name = "packages-env";
    paths = allPackages;
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/share"
    ];
  };

  cacertPath = "/sw/etc/ssl/certs/ca-bundle.crt";

  moduleTree = runLocalCommand "modules-${kernelPackage.version}"
    { inherit (kernelPackage) modDirVersion;
      modulesToLoad = allModulesToLoad;
      modDirPrefix = "${kernelPackage}";
      nativeBuildInputs = [ pkgs.binutils pkgs.kmod ];
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
      cmdparts=($insmod)  # expect "insmod <path_to_mod>[ <param1>...]"
      modconf=''${cmdparts[@]:2}

      # rewrite module src path to dest path
      srcmod=''${cmdparts[1]}
      dstmod=$(sed "s,${builtins.storeDir}/[^/]*,$out," <<< "$srcmod")

      # copy src to dest
      install -D $srcmod $dstmod -m 444

      # reconstitute insmod command
      echo "insmod $dstmod ''${modconf[@]}"
    done < <(modprobe \
        --dirname=$modDirPrefix \
        --set-version=$modDirVersion \
        --show-depends \
        --all \
        $modulesToLoad) \
      > insmod

    test -s insmod && $shell -n insmod

    # Regenerate modules.dep and friends
    depmod -w -b $out -F $modDirPrefix/System.map $modDirVersion

    oldSize=$(du -sb $modDirPrefix | cut -f1)
    newSize=$(du -sb $out          | cut -f1)
    diffSize=$(((newSize-oldSize) / 1000 / 1000))
    echo "$diffSize MB" >&2

    install -Dt $bin insmod
    '';

  initramfs = runLocalCommand "initramfs"
    { inherit busyboxStatic;
      inherit packageEnv;
      inherit moduleTree;
      inherit timeZone;

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
    install -d nix           -m  755
    install -d nix/store     -m 1775

    # Legacy /var
    ln -s /run      var/run
    ln -s /run/lock var/lock


    # Install static tools to initramfs root
    install $busyboxStatic/bin/busybox lib/busybox
    $busyboxStatic/bin/busybox --list | while read -r appname ; do
      ln lib/busybox bin/$appname
    done

    # Install kernel modules and their deps
    install -d lib/
    cp -R $moduleTree/lib/modules/ lib/


    # Becomes valid once the Nix store is mounted
    ln -s $packageEnv sw


    # Generate static sysconfig
    install -d etc

    ln -s /proc/self/mounts etc/mtab
    ln -s /sw/share/zoneinfo/$timeZone etc/localtime

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


    # Generate the shutdown script
    cat >etc/rc.shutdown <<EOF
    #! /bin/sh
    killall5 -TERM
    sleep 0.2
    killall5 -KILL
    mount / -o remount,ro
    sync
    poweroff -nf
    # shutdown script ends here
    EOF

    $shell -n etc/rc.shutdown
    chmod +w-w etc/rc.shutdown


    # Generate the initramfs init script
    cat >init <<EOF
    #! /bin/sh

    mount_robind() {
      local what=\''${1?What}
      local where=\''${2:-\$what}
      mount \$what \$where -o bind
      mount \$where        -o remount,bind,ro
    }

    rescue() {
      echo "Entering rescue shell!" >&2
      exec cttyhack sh
    }
    trap rescue EXIT
    set -eu

    set -a
    HOME=/root
    PATH=/sw/bin:/bin
    SHELL=/bin/sh
    LOCALE_ARCHIVE=/sw/lib/locale/locale-archive
    LANG=en_US.UTF-8
    LC_MESSAGES=C
    LC_COLLATE=C
    TZDIR=/sw/share/zoneinfo
    TZ=:/sw/share/zoneinfo/${timeZone}
    SSL_CERT_FILE=${cacertPath}
    CURL_CA_BUNDLE=${cacertPath}
    set +a


    mount proc   /proc    -t proc
    mount dev    /dev     -t devtmpfs
    mkdir /dev/pts
    mount devpts /dev/pts -t devpts
    mount sys    /sys     -t sysfs
    mount tmp    /tmp     -t tmpfs
    mount run    /run     -t tmpfs
    chmod 1777 /tmp


    install -d /run/log -o 0 -g 0 -m 750


    ln -nsf /dev/urandom /dev/random
    ln -nsf /proc/self/fd/0 /dev/stdin
    ln -nsf /proc/self/fd/1 /dev/stdout
    ln -nsf /proc/self/fd/2 /dev/stderr


    ${lib.concatStringsSep "\n" (map (modName: "modprobe ${modName}")
                                     allModulesToLoad)}


    ${lib.concatStringsSep "\n"
      (map guestMountVmShare vmShares)}


    mount_robind /etc
    mount_robind /var/empty
    echo ${hostname} > /proc/sys/kernel/hostname
    ip link set lo up
    dmesg -c > /run/log/dmesg.log


    trap - EXIT
    set +eu
    while : ; do
        cd /root
        setsid cttyhack sh
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

  kernelParams = [
    "apparmor=0"
    "audit=0"
    "console=ttyS0"
    "cryptomgr.notests"
    "elevator=noop"
    "oops=panic"
    "panic=-1"
    "quiet"
  ];

  run = writeScriptBin "run-vm" ''
    #! ${pkgs.runtimeShell} -eu
    exec ${qemuPackage}/bin/qemu-system-${qemuArch} \
      -nographic \
      -no-reboot \
      -enable-kvm \
      -machine q35,accel=kvm \
      -cpu host \
      -device intel-iommu \
      -m ${vmMemSize} \
      -smp ${toString vmNumCpus} \
      -object rng-random,filename=/dev/urandom,id=rng0 \
      -device virtio-rng-pci,rng=rng0 \
      ${vmSharesQemuFlags} \
      -net none \
      -kernel '${linuxEfiStub}' \
      -append '${toString kernelParams}' \
      -initrd '${initramfs}/initramfs.img' \
      "$@"
  '';
in
{
  inherit
    run
    moduleTree
    initramfs
  ;
}
