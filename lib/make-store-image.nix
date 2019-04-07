{ lib
, buildPackages
, name ? "nix-store-image"
, fileName ? "nix-store.sqsh"
, isReleaseBuild ? false
, rootPaths ? []
, closureInfo ? null
, excludePatterns ? []
}:

let
  inherit (buildPackages)
    runCommand
    squashfsTools
    xz
  ;

  closureInfoPrime = if closureInfo != null then closureInfo else
    buildPackages.closureInfo { inherit rootPaths; };

  compFlags = if isReleaseBuild
    then [ "-comp xz" "-Xbcj x86,arm" "-Xdict-size 100%" ]
    else [ "-comp gzip" "-Xcompression-level 1" ];
in

runCommand name
{ nativeBuildInputs = [ squashfsTools ] ++ lib.optional isReleaseBuild xz;

  closureInfo = closureInfoPrime;
  inherit isReleaseBuild;
  inherit fileName;
  inherit excludePatterns;
  inherit compFlags;
  passAsFile = [ "excludePatterns" ];

  # Caller must provide a predefined closureInfo or a set of store paths to
  # include in the image
  meta.broken = closureInfo == null && rootPaths == [];
}
''
mkdir root

xargs -P$NIX_BUILD_CORES -rn1 cp -a -t root/ < $closureInfo/store-paths
cp $closureInfo/registration root/.registration

mksquashfs root $fileName \
  -progress \
  -exit-on-error \
  -processors ''${NIX_BUILD_CORES:-1} \
  $compFlags \
  -no-recovery \
  -no-exports \
  -no-xattrs \
  -no-fragments \
  -no-duplicates \
  -force-uid 0 \
  -force-gid 0 \
  -wildcards -ef <(tr ' ' '\n' < $excludePatternsPath)

install -Dt $out $fileName -m 444
''
