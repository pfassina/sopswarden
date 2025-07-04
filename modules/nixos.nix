{ lib, sops-nix }:

{ config, pkgs, ... }:

let
  inherit (lib) types mkOption mkEnableOption mkIf mkMerge optional;
  cfg = config.services.sopswarden;
  sopswardenLib = import ../lib { nixpkgs = lib; };

  # Create the sync script with user configuration
  syncScript = sopswardenLib.mkSyncScript {
    inherit (cfg) secrets sopsFile ageKeyFile sopsConfigFile workingDirectory;
    inherit pkgs;
    inherit (cfg) rbwCommand;
  };

  # Create SOPS secrets configuration from user secrets
  sopsSecrets = sopswardenLib.mkSopsSecrets {
    inherit (cfg) secrets sopsFile defaultOwner defaultGroup defaultMode;
  };

  # Create secret accessors for easy consumption (IMPURE)
  secretAccessors = sopswardenLib.mkSecretAccessors {
    inherit config;
    inherit (cfg) secrets;
  };

  # Hash tracking for change detection (IMPURE)
  hashTracker = sopswardenLib.mkHashTracker {
    inherit (cfg) secrets hashFile;
  };

in
{
  imports = [
    sops-nix.nixosModules.sops
  ];

  options.services.sopswarden = {
    enable = mkEnableOption "sopswarden secrets management";

    secrets = mkOption {
      type = types.attrsOf (types.either sopswardenLib.secretTypes.simpleSecret sopswardenLib.secretTypes.complexSecret);
      default = { };
      description = ''
        Secrets to sync from Bitwarden. Can be either:
        - Simple: secret-name = "Bitwarden Item Name"
        - Complex: secret-name = { name = "Item"; user = "email"; type = "note"; field = "custom"; }
        
        The secret will be available in your NixOS configuration as:
        - secrets.secret-name
        
        Examples:
          wifi-password = "Home WiFi";
          api-key = { name = "Service API"; field = "api_key"; };
          db-password = { name = "Database"; user = "admin@example.com"; };
      '';
      example = {
        wifi-password = { name = "WiFi"; type = "note"; field = "password"; };
        api-key = "My Service";
        db-password = { name = "Database"; user = "admin@example.com"; };
      };
    };

    # File paths
    sopsFile = mkOption {
      type = types.path;
      default = /var/lib/sopswarden/secrets.yaml;
      description = "Path to the encrypted SOPS file";
    };

    ageKeyFile = mkOption {
      type = types.str;
      default = "~/.config/sops/age/keys.txt";
      description = "Path to the age private key file";
    };

    sopsConfigFile = mkOption {
      type = types.path;
      default = /var/lib/sopswarden/.sops.yaml;
      description = "Path to the .sops.yaml configuration file";
    };

    hashFile = mkOption {
      type = types.str;
      default = "/var/lib/sopswarden/.last-sync-hash";
      description = "Path to store the last sync hash for change detection";
    };

    workingDirectory = mkOption {
      type = types.nullOr types.str;
      default = "/var/lib/sopswarden";
      description = "Working directory for sync operations";
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
      # Create the sopswarden directory
      system.activationScripts.sopswarden-setup = {
        text = ''
          mkdir -p /var/lib/sopswarden
          chmod 750 /var/lib/sopswarden
          chown root:root /var/lib/sopswarden
        '';
        deps = [ ];
      };

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
        inherit (sopswardenLib) mkSecret; # Export helper function
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
        "⚠️  sopswarden: secrets file has changed since last sync. Run 'sopswarden-sync' to update encrypted secrets.";
    })
  ]);
}
