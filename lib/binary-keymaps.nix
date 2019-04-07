{ runCommand, kbd }:

/**
 * Generate a tree of binary keymaps, suitable for consumption by busybox
 * `loadkeys`.
 *
 * Always includes the default keymap.
 */
{ keymaps ? [ ] # e.g., "no-latin1"
}:

runCommand "binary-keymaps"
{ nativeBuildInputs = [ kbd ];
  inherit kbd;
  inherit keymaps;
  allowSubstitutes = false;
  preferLocalBuild = true;
}
''
keymaps+=" defkeymap"
mkdir -p "$out/share/keymaps/i386/qwerty"
for kmap in $keymaps ; do
  loadkeys -b "$kbd/share/keymaps/i386/qwerty/$kmap.map.gz" \
    | gzip -v -9n > "$out/share/keymaps/i386/qwerty/$kmap.bmap.gz"
done
''
