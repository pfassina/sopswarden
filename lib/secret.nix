# lib/secret.nix
{ lib, config }:

let
  esc = lib.escape [ "$" "}" ];
in rec {
  ## 1.  The default: just a path (safe, zero copy in /nix/store)
  path = p: p;

  ## 2.  Runtime-string for template / extraConfig use-cases
  secretString = secretPath:
    "${esc "${config.sops.placeholder.${secretPath.name}}"}";

  ## 3.  Literal string *in the store* (unsafe, but offered knowingly)
  secretLiteral = secretPath:
    builtins.readFile secretPath;
}