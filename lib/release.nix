with (import <nixpkgs>{});

let
  buildPackages = pkgs;
in

rec {

  inherit (import ./. { inherit lib buildPackages; })
    buildBinaryKeymaps
    makeStoreImage
    makeInitramfsImage
    ;

  examples.initramfsImage = makeInitramfsImage {
    root = buildPackages.runCommand "root"
      { allowSubstitutes = false;
        preferLocalBuild = true;
      }
      ''
      install -d $out/dev $out/proc $out/run $out/sys $out/tmp
      '';
  };

  examples.storeImage_small = makeStoreImage {
    rootPaths = with pkgs; [
      bash
      nano
    ];
    excludePatterns = [
      "*.la"
      "*/share/locale/*"
    ];
  };

}