{ lib, sops-nix }:

{ config, pkgs, ... }:

let
  inherit (lib) types mkOption mkEnableOption mkIf mkMerge optional;
  cfg = config.services.sopswarden;
  sopswardenLib = import ../lib { nixpkgs = lib; };

  # Create the sync script with direct secrets configuration
  syncScript = sopswardenLib.mkSyncScript {
    inherit (cfg) rbwCommand sopsFile ageKeyFile sopsConfigFile;
    secrets = cfg.secrets;
    inherit pkgs;
  };

  # Convert to absolute path while avoiding store path context
  # This satisfies SOPS-nix requirements without caching issues
  absoluteSopsFile = 
    if lib.hasPrefix "/" cfg.sopsFile 
    then cfg.sopsFile  # Already absolute string
    else 
      # Use unsafeDiscardStringContext to strip any store context from relative paths
      # This keeps evaluation pure while allowing external file modifications
      builtins.unsafeDiscardStringContext cfg.sopsFile;

  # Create SOPS secrets configuration from direct secrets
  sopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = cfg.secrets;
    sopsFile = absoluteSopsFile;
    defaultOwner = cfg.defaultOwner;
    defaultGroup = cfg.defaultGroup;
    defaultMode = cfg.defaultMode;
  };

  # Create secret accessors for easy consumption
  # Always return SOPS paths - validation happens at runtime
  secretAccessors = sopswardenLib.mkSecretAccessors {
    inherit config;
    secrets = cfg.secrets;
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

    # SOPS configuration
    sopsFile = mkOption {
      type = types.str;
      default = "/var/lib/sopswarden/secrets.yaml";
      description = ''
        Path to the encrypted SOPS file.
        
        Uses absolute path by default to maintain pure evaluation.
        Can be relative (e.g., "./secrets.yaml") or absolute (e.g., "/etc/nixos/secrets.yaml").
        Relative paths are resolved using unsafeDiscardStringContext to avoid store issues.
      '';
    };

    ageKeyFile = mkOption {
      type = types.str;
      default = "/home/${config.users.users.${cfg.defaultOwner}.name}/.config/sops/age/keys.txt";
      description = "Path to the age private key file";
    };

    sopsConfigFile = mkOption {
      type = types.str;
      default = "./.sops.yaml";
      description = "Path to the .sops.yaml configuration file";
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
      description = ''
        Default owner for secret files and the user account that has rbw access.
        
        IMPORTANT: This user must have rbw configured and unlocked for sopswarden to work.
        For most setups, this should be set to your primary user account (e.g., "myuser").
      '';
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
      description = "Whether to install sopswarden dependencies (rbw, sops, age) system-wide";
    };

    installSyncCommand = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to make sopswarden-sync command available system-wide";
    };


  };

  config = mkIf cfg.enable (mkMerge [
    # Always configure age and export secret accessors
    {
      sops = {
        defaultSopsFormat = "yaml";
        
        age = {
          keyFile = cfg.ageKeyFile;
          generateKey = true;
        };
      };

      # Export secrets for easy access in other modules
      _module.args = { 
        secrets = secretAccessors;
        sopswardenSecrets = secretAccessors; # Alternative name
      };
    }

    # SOPS secrets configuration - always configure when secrets are defined
    (mkIf (cfg.secrets != {}) {
      sops.defaultSopsFile = absoluteSopsFile;
      sops.secrets = sopsSecrets;
      # Disable validation since we manage files externally via systemd services
      sops.validateSopsFiles = false;
    })

    # Runtime secret synchronization and validation
    (mkIf (cfg.secrets != {}) {
      # Create directory for sopswarden files
      systemd.tmpfiles.rules = [
        "d /var/lib/sopswarden 0755 ${cfg.defaultOwner} ${cfg.defaultGroup} -"
      ];

      # Service to sync secrets from Bitwarden before system starts
      systemd.services.sopswarden-sync = {
        description = "Fetch secrets from Bitwarden into SOPS file";
        path = with pkgs; [ cfg.rbwPackage sops age ];
        environment = {
          SOPS_FILE = cfg.sopsFile;
          SOPS_CONFIG_FILE = cfg.sopsConfigFile;
          AGE_KEY_FILE = cfg.ageKeyFile;
          HOME = config.users.users.${cfg.defaultOwner}.home;
          XDG_CONFIG_HOME = "${config.users.users.${cfg.defaultOwner}.home}/.config";
          XDG_DATA_HOME = "${config.users.users.${cfg.defaultOwner}.home}/.local/share";
        };
        serviceConfig = {
          Type = "oneshot";
          User = cfg.defaultOwner;
          Group = cfg.defaultGroup;
          WorkingDirectory = config.users.users.${cfg.defaultOwner}.home;
        };
        script = ''
          echo "🔄 Syncing secrets from Bitwarden..."
          ${syncScript}/bin/sopswarden-sync
        '';
        wantedBy = [ "sysinit.target" ];
        before = [ "sops-nix.service" ];
      };

      # Service to validate SOPS file after sync
      systemd.services.sopswarden-validate = {
        description = "Validate SOPS file after sync";
        path = with pkgs; [ sops ];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.defaultOwner;
          Group = cfg.defaultGroup;
        };
        script = ''
          echo "🔍 Validating SOPS file: ${cfg.sopsFile}"
          if [[ -f "${cfg.sopsFile}" ]]; then
            sops --decrypt "${cfg.sopsFile}" > /dev/null
            echo "✅ SOPS file validation successful"
          else
            echo "⚠️  SOPS file not found: ${cfg.sopsFile}"
            exit 1
          fi
        '';
        requires = [ "sopswarden-sync.service" ];
        after = [ "sopswarden-sync.service" ];
        wantedBy = [ "sysinit.target" ];
        before = [ "sops-nix.service" ];
      };
    })

    # Package installation
    (mkIf cfg.installPackages {
      environment.systemPackages = sopswardenLib.defaultPackages pkgs;
    })

    # Sync command installation  
    (mkIf cfg.installSyncCommand {
      environment.systemPackages = [ syncScript ];
    })


    # Informational messages
    {
      warnings = optional (cfg.secrets != {})
        "ℹ️  sopswarden: Secrets will be synced automatically via systemd services during system activation.";
    }
  ]);
}