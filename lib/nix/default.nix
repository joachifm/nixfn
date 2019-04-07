let
  importLib = x: import x { inherit lib; };
  lib = {
    list = importLib ./list.nix;
    string = importLib ./string.nix;
  };
in lib
