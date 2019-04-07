let
  # Last updated Nov 16, 2018
  nixpkgsrev = "5632aad4739c2fc342ea280cee47b5213f799491";
  nixexprs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgsrev}.tar.gz";
    sha256 = "0wlzdhcq1h1pjcs9vlf4xvcizpl9yysh8p1wfrp9mkhqgd5jnj5g";
  };
in args: import nixexprs (args // { overlays = [
  (import ./overlay.nix)
]; })
