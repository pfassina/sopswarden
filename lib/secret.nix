# lib/secret.nix
{ lib }:

let
  mkSentinel = name: "__SOPSWARDEN_${lib.strings.toUpper name}__";
in rec {
  # 1. safest: let modules that want a file use the path directly
  path = p: p;

  # 2. string option → emit sentinel, to be swapped at activation
  secretString = secretPath: mkSentinel (builtins.baseNameOf secretPath);

  # 3. escape hatch – embeds plain text in the store (discouraged)
  secretLiteral = secretPath: builtins.readFile secretPath;

  inherit mkSentinel;
}