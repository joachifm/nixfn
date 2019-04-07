{ lib, buildPackages }:

{

  buildBinaryKeymaps = import ./binary-keymaps.nix {
    inherit (buildPackages) runCommand kbd;
  };

  makeInitramfsImage = args: import ./make-initramfs-image.nix ({
    inherit lib buildPackages;
  } // args);

  makeStoreImage = args: import ./make-store-image.nix ({
    inherit lib buildPackages;
  } // args);

}
