# lib/secret.nix
{ lib, ... }:

let
  mkSentinel = name: "__SOPSWARDEN_${name}__";
in rec {
  # Export mkSentinel for use in the module
  inherit mkSentinel;
  
  ## 1.  The default: just a path (safe, zero copy in /nix/store)
  path = p: p;

  ## 2.  Runtime-string that emits sentinel for activation-time substitution
  secretString = secretPath:
    let
      # Extract the secret name from the path like "/run/secrets/immich-url" -> "immich-url"
      secretName = if builtins.isString secretPath 
                   then builtins.baseNameOf secretPath
                   else if secretPath ? name 
                   then secretPath.name
                   else throw "secretString: unable to determine secret name from ${toString secretPath}";
    in
    mkSentinel secretName;

  ## 3.  Literal string *in the store* (unsafe, but offered knowingly)
  secretLiteral = secretPath:
    builtins.readFile secretPath;
}