{ nixpkgs }:

let
  inherit (nixpkgs) types mkOption;
  lib = nixpkgs;
in
rec {
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

  # Core function to create a parameterized sync script
  mkSyncScript = {
    pkgs,
    secrets ? {},
    sopsFile ? "./secrets.yaml", 
    ageKeyFile ? "~/.config/sops/age/keys.txt",
    sopsConfigFile ? "./.sops.yaml",
    rbwPackage ? pkgs.rbw,
    rbwCommand ? "${rbwPackage}/bin/rbw",
    forceSync ? false
  }:
    pkgs.writeShellScriptBin "sopswarden-sync" (import ./sync-script.nix {
      inherit secrets sopsFile ageKeyFile sopsConfigFile rbwCommand forceSync;
      inherit normalizeSecretDef;
      inherit lib;
    });

  # Default packages needed for sopswarden
  defaultPackages = pkgs: with pkgs; [
    rbw    # Bitwarden CLI - core functionality
    sops   # Secret encryption 
    age    # Encryption backend
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
      # Always return the SOPS secret path - never read content at evaluation time
      # This keeps evaluation pure and defers all file access to runtime
      config.sops.secrets.${name}.path
    ) secrets;

}