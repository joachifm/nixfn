{ lib, buildDiskAppliance }:
with lib;

{
  diskApp1 = buildDiskAppliance {
    vmMemSize = "512M";

    vmDisks = [
      { name = "disk1"; size = "15G"; }
      { name = "disk2"; size = "15G"; }
    ];

    preCommand = ''
      set -x
      touch pause-after-command
    '';

    command = ''
      diskDev=/dev/vda
      flock "$diskDev" sfdisk "$diskDev" <<EOF
      label: dos
      1M   100M L *
      101M -    L -
      EOF

      bootPart=''${diskDev}1
      rootPart=''${diskDev}2

      keyfile=/xchg/$(escape_filepath $rootPart).key
      if ! [ -e "$keyfile" ] ; then
        genkey_4096_hex > "$keyfile"
      fi

      yes | cryptsetup luksFormat "$rootPart" "$keyfile"
      cryptsetup open "$rootPart" luks-root -d "$keyfile"
      blkDev=/dev/mapper/luks-root

      pool=tank
      newpool
      newfs root 10G xfs
      newfs home 10G xfs+reflink
      newfs swap1 8G swap

      swapon /dev/tank/swap1

      ${concatStringsSep "" (genList (i: ''
        username=user${toString i}

        dupfs home home-$username
        snapfs home-$username home-$username-pristine
        snapfs home-$username

        mkdir -m 700 -p /home/$username
        mountfs home-$username /home/$username

        dd if=/dev/urandom of=/home/$username/data.bin bs=512 count=4096
        cp /home/$username/data.bin /home/$username/data.bin.copy

        snapfs home-$username
      '') 5)}

      diskDev=/dev/vdb
      flock "$diskDev" sfdisk "$diskDev" <<EOF
      label: dos
      1M - L -
      EOF
      keyfile=/xchg/$(escape_filepath /dev/vdb1).key
      if ! [ -e "$keyfile" ] ; then
        genkey_4096_hex > "$keyfile"
      fi
      yes | cryptsetup luksFormat /dev/vdb1 "$keyfile"
      cryptsetup open /dev/vdb1 luks-data -d "$keyfile"
      blkDev=/dev/mapper/luks-data

      vgextend tank /dev/mapper/luks-data
      lvextend -l 100%FREE tank/lvpool

      umount /home/user0
      lvconvert --mergethin tank/home-user0-pristine
    '';
  };
}
