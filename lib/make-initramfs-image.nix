{ lib
, buildPackages
, isReleaseBuild ? false
, fileName ? "initramfs.img"
, root
}:

let
  inherit (buildPackages)
    runCommand
    ;
in

runCommand "initramfs"
{ allowSubstitutes = false;
  preferLocalBuild = true;

  nativeBuildInputs = with buildPackages; [ cpio ]
    ++ lib.optional isReleaseBuild pigz;

  inherit fileName;
  inherit root;
  compress = if isReleaseBuild
    then "pigz --no-time --processes $NIX_BUILD_CORES --best"
    else "cat";
}
''
find "$root" -mindepth 1 -printf '%P\0' \
  | LC_ALL=C sort -z \
  | cpio -D "$root" -0 -o -H newc --reproducible -R +0:+0 \
  | $compress \
  > $fileName
install -Dt $out $fileName -m 444
''
