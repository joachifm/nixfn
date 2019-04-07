{ buildAppliance

, buildPackages
, hostPackages ? buildPackages
, targetPackages ? hostPackages
}:

let
  inherit (buildPackages)
    lib
    runCommand
  ;
in

with lib;

let
  lvmConfCommonText = with targetPackages; ''
    devices {
      cache_dir = "/var/cache/lvm"
    }

    allocation {
      thin_pool_zero = 0
      thin_pool_chunk_size_policy = "performance"
    }

    log {
      syslog = 0
    }

    backup {
      backup_dir = "/var/lib/lvm/backup"
      archive_dir = "/var/lib/lvm/archive"
    }

    global {
      locking_dir = "/run/lock/lvm"
      thin_check_executable = "${thin-provisioning-tools}/bin/thin_check"
      thin_dump_executable = "${thin-provisioning-tools}/bin/thin_dump"
      thin_repair_executable = "${thin-provisioning-tools}/bin/thin_repair"
      cache_check_executable = "${thin-provisioning-tools}/bin/cache_check"
      cache_dump_executable = "${thin-provisioning-tools}/bin/cache_dump"
      cache_repair_executable = "${thin-provisioning-tools}/bin/cache_repair"
      fsadm_executable = "${coreutils}/bin/true"
      notify_dbus = 0
    }

    activation {
      thin_pool_autoextend_threshold = 100
    }
  '';

  lvmConfText = ''
    ${lvmConfCommonText}

    devices {
      obtain_device_list_from_udev = 1
      external_device_info_source = "none"
    }

    global {
      use_lvmetad = 0
    }

    activation {
      monitoring = 0
    }
  '';
in

let
  udevRulesDir = { packages }: runCommand "udev-rules.d"
    { inherit packages; }
    ''
      mkdir $out
      find $packages -path '*/udev/rules.d/*.rules' -exec ln -s -t $out '{}' +

      disabledRules=("60-cdrom_id.rules")
      for ruleName in "''${disabledRules[@]}" ; do
        if ! [[ -r $out/$ruleName ]] ; then
          echo "no such rule: $ruleName; skipping" >&2
          continue
        fi
        ln -nsf /dev/null $out/$ruleName
      done
    '';

  lvmConfFromText = text: runCommand "lvm.conf"
    { nativeBuildInputs = with buildPackages; [ lvm2 ];
      inherit text;
      passAsFile = [ "text" ];
    }
    ''
      mkdir $out
      cat $textPath >$out/lvm.conf
      LVM_SYSTEM_DIR=$out lvmconfig --validate
    '';
in

let
  lvmConf = lvmConfFromText lvmConfText;

  udevRules = udevRulesDir {
    packages = with targetPackages; [ cryptsetup eudev lvm2 ];
  };
in

args:

let
  # input args sans attrs we'll want to extend/derive from; everything
  # else is overridden.
  args' = removeAttrs args [
    "modulesToLoad"
    "packages"
    "preCommand"
  ];
in

buildAppliance (args' // {
  modulesToLoad = [
    "aes-x86-64"

    "aesni_intel"
    "crc32c_intel"
    "sha1_ssse3"

    "dm-crypt"
    "dm-integrity"
    "dm-snapshot"
    "dm-thin-pool"

    "vfat"
      "nls-cp437"
      "nls-iso8859-1"
    "xfs"

    "virtio-blk"
  ] ++ (args.modulesToLoad or [ ]);

  packages = pkgs: (args.packages or [ ]) ++ (with pkgs; [
    coreutils
    utillinuxMinimal

    cryptsetup
    eudev
    lvm2

    dosfstools
    e2fsprogs
    xfsprogs

    strace
  ]);

  preCommand = ''
    . ${./storage-lib.sh}

    mkdir -m 700 -p /var/lib/udev
    ln -s /var/lib/udev /etc/udev

    ln -s ${udevRules} /etc/udev/rules.d
    udevadm hwdb --update

    udevd --daemon

    udevadm trigger --type=devices    --action=add
    udevadm trigger --type=subsystems --action=add
    udevadm settle

    mkdir -m 700 -p /etc/lvm
    ln -s ${lvmConf}/lvm.conf /etc/lvm/lvm.conf
    mkdir -m 700 -p /var/cache/lvm /var/lib/lvm
    mkdir -m 700 -p /run/lvm
    ln -s /var/lib/lvm/archive /etc/lvm/archive
    ln -s /var/lib/lvm/backup /etc/lvm/backup
  '' + (args.preCommand or "");
})
