{ prevStdenv }:

let
  stdenv = prevStdenv.override (old: {
    extraBuildInputs = old.extraBuildInputs or [ ] ++ [ ];
  });
in

stdenv // {
  mkDerivation = args0:
    let
      # Set default args
      args1 = {
        enableParallelBuilding = true;
      } // args0;

      # Override args
      args2 = args1 // {
        NIX_CFLAGS_COMPILE = "-pipe -fno-plt"
          + " " + toString (args1.NIX_CFLAGS_COMPILE or "");

        NIX_CFLAGS_LINK = "-pipe -fuse-ld=gold -Wl,-O1,--sort-common,-z,combreloc"
          + " " + toString (args1.NIX_CFLAGS_LINK or "");

        NIX_LDFLAGS_AFTER = "--build-id=none --hash-style=gnu"
          + " " + toString (args1.NIX_LDFLAGS_AFTER or "");

        NIX_LDFLAGS_BEFORE = ""
          + " " + toString (args1.NIX_LDFLAGS_BEFORE or "");
      };
    in stdenv.mkDerivation args2;
}
