{ writeScript
, runtimeShell
, mountProg ? "/run/current-system/sw/bin/mount"
}:

with builtins;

/**
 * Generate a shell-script that mounts a fixed set of store-paths to a given
 * mount point.
 */
{ storePaths }:

assert isList storePaths && storePaths != [];

let
  mountSingle = ''
    ${mountProg} ${toString storePaths} "$where" -o bind
    ${mountProg}                        "$where" -o remount,bind,ro
  '';

  mountMulti = ''
    ${mountProg} -t overlay -o lowerdir=${concatStringsSep ":" storePaths} none "$where"
  '';
in

writeScript "mount.sh" ''
#! ${runtimeShell}
where=''${1?Mount point}
${if length storePaths == 1
  then mountSingle
  else mountMulti}
''
