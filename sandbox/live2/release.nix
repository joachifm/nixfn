{ nixpkgs ? import ./nixpkgs { } }:

rec {

  build = nixpkgs.recurseIntoAttrs {
    inherit (import ./. { inherit nixpkgs; })
      livefs
    ;
  };

  mkApp = import ./appliance.nix { inherit nixpkgs; };

  app1 = mkApp {
    hostname = "app1";
    packages = ps: with ps; [
      strace

      lynx
      mksh
      tmux
      zile

      dropbear
      wpa_supplicant
      dhcpcd
    ];
  };

}
