# lib/secret.nix
{ lib }:

rec {
  # 1. safest: let modules that want a file use the path directly
  path = p: p;

  # 2. string option → emit SOPS placeholder for template resolution
  secretString = secretPath: 
    # Emit a SOPS placeholder that will be resolved by sops.templates
    # Use string concatenation to avoid bash variable expansion issues
    "$" + "{config.sops.placeholder.${builtins.baseNameOf secretPath}}";

  # 3. escape hatch – embeds plain text in the store (discouraged)
  secretLiteral = secretPath: builtins.readFile secretPath;

  # Legacy sentinel support (deprecated, will be removed)
  mkSentinel = name: "__SOPSWARDEN_${lib.strings.toUpper name}__";
}