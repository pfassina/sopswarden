{ nixpkgs }:

let
  inherit (nixpkgs) types mkOption removeSuffix;
in
rec {
  # Core function to create a parameterized sync script
  mkSyncScript =
    { pkgs
    , secretsFile ? "./secrets.nix"
    , sopsFile ? "./secrets.yaml"
    , ageKeyFile ? "~/.config/sops/age/keys.txt"
    , sopsConfigFile ? "./.sops.yaml"
    , rbwPackage ? pkgs.rbw
    , rbwCommand ? "${rbwPackage}/bin/rbw"
    , forceSync ? false
    , workingDirectory ? null
    }:
    pkgs.writeShellScriptBin "sopswarden-sync" (import ./sync-script.nix {
      inherit secretsFile sopsFile ageKeyFile sopsConfigFile rbwCommand forceSync workingDirectory;
    });

  # Default packages needed for sopswarden
  defaultPackages = pkgs: with pkgs; [
    rbw # Bitwarden CLI - core functionality
    sops # Secret encryption 
    age # Encryption backend
    jq # JSON parsing
  ];

  # Helper function to simplify secret definitions  
  mkSecret = name: attrs: {
    sopsFile = attrs.file or ./secrets.yaml;
    key = attrs.key or name;
    owner = attrs.owner or "root";
    group = attrs.group or "root";
    mode = attrs.mode or "0400";
  };

  # Secret definition types for validation
  secretTypes = {
    simpleSecret = types.str;
    complexSecret = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Name of the Bitwarden item";
        };
        user = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Username/email to disambiguate items";
        };
        type = mkOption {
          type = types.enum [ "login" "note" ];
          default = "login";
          description = "Type of Bitwarden item";
        };
        field = mkOption {
          type = types.str;
          default = "password";
          description = "Field to extract from the item";
        };
      };
    };
  };

  # Helper function to normalize secret definitions
  normalizeSecretDef = secretDef:
    if builtins.isString secretDef then {
      name = secretDef;
      user = null;
      type = "login";
      field = "password";
    } else
      secretDef // {
        type = secretDef.type or "login";
        field = secretDef.field or "password";
        user = secretDef.user or null;
      };

  # Function to create SOPS secrets configuration
  mkSopsSecrets = { secrets, sopsFile ? ./secrets.yaml, defaultOwner ? "root", defaultGroup ? "root", defaultMode ? "0400" }:
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = mkSecret name {
            inherit sopsFile defaultOwner defaultMode;
            owner = defaultOwner;
            group = defaultGroup;
          };
        })
        (builtins.attrNames secrets)
    );

  # Function to create secret accessor functions (IMPURE - reads at evaluation time)
  mkSecretAccessors = { config, secrets }:
    builtins.mapAttrs
      (name: _:
        let
          secretPath = config.sops.secrets.${name}.path;
          # Try to read the secret file if it exists (during rebuild on running system)
          # Fall back to file path if not available (during initial build)
          tryReadSecret = builtins.tryEval (removeSuffix "\n" (builtins.readFile secretPath));
        in
        if tryReadSecret.success
        then tryReadSecret.value
        else secretPath
      )
      secrets;

  # Hash-based change detection (IMPURE - reads hash file)
  mkHashTracker = { secretsFile, hashFile }:
    let
      secretsHash = builtins.hashFile "sha256" secretsFile;
      lastSyncHash =
        if builtins.pathExists hashFile
        then removeSuffix "\n" (builtins.readFile hashFile)
        else "";
    in
    {
      inherit secretsHash lastSyncHash;
      hasChanged = secretsHash != lastSyncHash;
    };
}
