{ lib, sops-nix }:

{ config, pkgs, ... }:

let
  inherit (lib) types mkOption mkEnableOption mkIf mkMerge optional;
  cfg = config.services.sopswarden;
  sopswardenLib = import ../lib { nixpkgs = lib; };

  # Create the sync script with user configuration
  syncScript = sopswardenLib.mkSyncScript {
    inherit (cfg) rbwCommand secretsFile sopsFile ageKeyFile sopsConfigFile workingDirectory;
    inherit pkgs;
  };

  # Create SOPS secrets configuration from user secrets
  sopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = cfg.secrets;
    sopsFile = cfg.sopsFile;
    defaultOwner = cfg.defaultOwner;
    defaultGroup = cfg.defaultGroup;
    defaultMode = cfg.defaultMode;
  };

  # Create secret accessors for easy consumption
  secretAccessors = sopswardenLib.mkSecretAccessors {
    inherit config;
    secrets = cfg.secrets;
  };

  # Hash tracking for change detection
  hashTracker = sopswardenLib.mkHashTracker {
    secretsFile = cfg.secretsFile;
    hashFile = cfg.hashFile;
  };

in
{
  imports = [
    sops-nix.nixosModules.sops
  ];

  options.services.sopswarden = {
    enable = mkEnableOption "sopswarden secrets management";

    # Core configuration
    secrets = mkOption {
      type = types.attrsOf (types.either sopswardenLib.secretTypes.simpleSecret sopswardenLib.secretTypes.complexSecret);
      default = {};
      description = ''
        Attribute set of secrets to sync from Bitwarden.
        
        Simple form: secretName = "Bitwarden Item Name";
        Complex form: secretName = { name = "Item Name"; user = "email"; type = "note"; field = "fieldname"; };
      '';
      example = {
        wifi-password = { name = "WiFi"; type = "note"; field = "password"; };
        api-key = "My Service";
        db-password = { name = "Database"; user = "admin@example.com"; };
      };
    };

    # File paths
    secretsFile = mkOption {
      type = types.path;
      default = ./secrets.nix;
      description = "Path to the secrets.nix file containing secret definitions";
    };

    sopsFile = mkOption {
      type = types.path;
      default = ./secrets.yaml;
      description = "Path to the encrypted SOPS file";
    };

    ageKeyFile = mkOption {
      type = types.str;
      default = "/home/${config.users.users.${cfg.defaultOwner}.name}/.config/sops/age/keys.txt";
      description = "Path to the age private key file";
    };

    sopsConfigFile = mkOption {
      type = types.path;
      default = ./.sops.yaml;
      description = "Path to the .sops.yaml configuration file";
    };

    hashFile = mkOption {
      type = types.str;
      default = builtins.dirOf (toString cfg.secretsFile) + "/.last-sync-hash";
      description = "Path to store the last sync hash for change detection";
    };

    workingDirectory = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Working directory for sync operations. If null, uses directory containing secretsFile";
    };

    # rbw configuration
    rbwPackage = mkOption {
      type = types.package;
      default = pkgs.rbw;
      description = "rbw package to use for Bitwarden access";
    };

    rbwCommand = mkOption {
      type = types.str;
      default = "${cfg.rbwPackage}/bin/rbw";
      description = "Full command to use for rbw operations";
    };

    # SOPS defaults
    defaultOwner = mkOption {
      type = types.str;
      default = "root";
      description = "Default owner for secret files";
    };

    defaultGroup = mkOption {
      type = types.str;
      default = "root";
      description = "Default group for secret files";
    };

    defaultMode = mkOption {
      type = types.str;
      default = "0400";
      description = "Default file mode for secret files";
    };

    # Package management
    installPackages = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to install sopswarden dependencies (rbw, sops, age, jq) system-wide";
    };

    installSyncCommand = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to make sopswarden-sync command available system-wide";
    };

    # Change detection and warnings
    enableChangeDetection = mkOption {
      type = types.bool;
      default = true;
      description = "Enable warnings when secrets.nix changes since last sync";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Basic SOPS configuration
    {
      sops = {
        defaultSopsFile = cfg.sopsFile;
        defaultSopsFormat = "yaml";
        
        age = {
          keyFile = cfg.ageKeyFile;
          generateKey = true;
        };

        secrets = sopsSecrets;
      };

      # Export secrets for easy access in other modules
      _module.args = { 
        secrets = secretAccessors;
        sopswardenSecrets = secretAccessors; # Alternative name
      };
    }

    # Package installation
    (mkIf cfg.installPackages {
      environment.systemPackages = sopswardenLib.defaultPackages pkgs;
    })

    # Sync command installation  
    (mkIf cfg.installSyncCommand {
      environment.systemPackages = [ syncScript ];
    })

    # Change detection warnings
    (mkIf cfg.enableChangeDetection {
      warnings = optional hashTracker.hasChanged
        "⚠️  sopswarden: secrets.nix has changed since last sync. Run 'sopswarden-sync' to update encrypted secrets.";
    })
  ]);
}