/*
 * SysV init compatibility wrappers for runit-init.
 */

{ runCommand
, runit
, binsh ? "/bin/sh"
}:

runCommand "runit-sysvinit"
{ allowSubstitutes = false;
  preferLocalBuild = true;
  inherit
    binsh
    runit;
}
''
mkdir -p $out/bin

cat >$out/bin/reboot <<EOF
#! $binsh
exec $runit/bin/runit-init 6
EOF
chmod +x $out/bin/reboot

cat >$out/bin/poweroff <<EOF
#! $binsh
exec $runit/bin/runit-init 0
EOF
chmod +x $out/bin/poweroff
''
