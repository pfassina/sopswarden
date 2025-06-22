{ nixpkgs }:

let
  inherit (nixpkgs) types mkOption;
  lib = nixpkgs;
in
rec {
  # Core function to create a parameterized sync script
  mkSyncScript = {
    pkgs,
    secretsFile ? "./secrets.nix",
    sopsFile ? "./secrets.yaml", 
    ageKeyFile ? "~/.config/sops/age/keys.txt",
    sopsConfigFile ? "./.sops.yaml",
    rbwPackage ? pkgs.rbw,
    rbwCommand ? "${rbwPackage}/bin/rbw",
    forceSync ? false,
    workingDirectory ? null
  }:
    pkgs.writeShellScriptBin "sopswarden-sync" (import ./sync-script.nix {
      inherit secretsFile sopsFile ageKeyFile sopsConfigFile rbwCommand forceSync workingDirectory;
    });

  # Default packages needed for sopswarden
  defaultPackages = pkgs: with pkgs; [
    rbw    # Bitwarden CLI - core functionality
    sops   # Secret encryption 
    age    # Encryption backend
    jq     # JSON parsing
  ];

  # Secret definition types for validation
  secretTypes = {
    simpleSecret = types.str;
    complexSecret = types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Bitwarden item name";
        };
        user = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Username for login items with multiple accounts";
        };
        type = mkOption {
          type = types.enum [ "login" "note" ];
          default = "login";
          description = "Bitwarden item type";
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
      map (name: {
        inherit name;
        value = {
          sopsFile = sopsFile;
          key = name;
          owner = defaultOwner;
          group = defaultGroup;
          mode = defaultMode;
        };
      }) (builtins.attrNames secrets)
    );

  # Function to create secret accessor functions
  mkSecretAccessors = { config, secrets }:
    builtins.mapAttrs (name: _:
      let
        secretPath = config.sops.secrets.${name}.path;
        # Read content when possible (requires --impure)
        tryReadSecret = builtins.tryEval (
          lib.removeSuffix "\n" (builtins.readFile secretPath)
        );
      in
      if tryReadSecret.success
      then tryReadSecret.value  # Return actual content
      else secretPath           # Fallback to path if reading fails
    ) secrets;

  # Hash-based change detection
  mkHashTracker = { secretsFile, hashFile }:
    let
      secretsHash = builtins.hashFile "sha256" secretsFile;
      lastSyncHash = if builtins.pathExists hashFile
        then lib.removeSuffix "\n" (builtins.readFile hashFile)
        else "";
    in
    {
      inherit secretsHash lastSyncHash;
      hasChanged = secretsHash != lastSyncHash;
    };
}