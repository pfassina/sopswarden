# lib/secret.nix
{ lib, config }:

let
  esc = lib.escape [ "$" "}" ];
in rec {
  ## 1.  The default: just a path (safe, zero copy in /nix/store)
  path = p: p;

  ## 2.  Runtime-string for template / extraConfig use-cases
  secretString = secretPath:
    let
      # Extract the secret name from the path like "/run/secrets/immich-url" -> "immich-url"
      secretName = if builtins.isString secretPath 
                   then builtins.baseNameOf secretPath
                   else if secretPath ? name 
                   then secretPath.name
                   else throw "secretString: unable to determine secret name from ${toString secretPath}";
    in
    # Use the SOPS placeholder if it exists, otherwise fall back to the path
    config.sops.placeholder.${secretName} or secretPath;

  ## 3.  Literal string *in the store* (unsafe, but offered knowingly)
  secretLiteral = secretPath:
    builtins.readFile secretPath;
}