/*
 * SysV init compatibility wrappers for suckless init.
 */

{ runCommand
, binsh ? "/bin/sh"
, killProg ? "/run/current-system/sw/bin/kill"
}:

runCommand "sinit-sysvinit-0"
{ inherit
    binsh
    killProg
  ;
  allowSubstitutes = false;
  preferLocalBuild = true;
}
''
echo "Generating wrappers ..."

wrappers=()

cat >reboot <<EOF
#! $binsh
exec "$killProg" -SIGINT 1
EOF
wrappers+=("reboot")

cat >poweroff <<EOF
#! $binsh
exec "$killProg" -SIGUSR1 1
EOF
wrappers+=("poweroff")

cat >telinit <<EOF
#! $binsh
cmd=$out/bin/poweroff
case "\$1" in
(6) cmd=$out/bin/reboot ;;
esac
exec "\$cmd"
EOF
wrappers+=("telinit")

echo "Syntax checking wrappers ..."
for prog in "''${wrappers[@]}" ; do
  $shell --posix -n "$prog"
done

echo "Copying to out ..."
install -m 555 -Dt "$out"/bin "''${wrappers[@]}"
''
