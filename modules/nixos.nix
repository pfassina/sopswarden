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

  # Create SOPS secrets configuration from direct secrets
  sopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = cfg.secrets;
    sopsFile = cfg.sopsFile;
    defaultOwner = cfg.defaultOwner;
    defaultGroup = cfg.defaultGroup;
    defaultMode = cfg.defaultMode;
  };

  # Create secret accessors for easy consumption
  # Only create accessors when SOPS file exists, otherwise use placeholders
  secretAccessors = 
    if builtins.pathExists cfg.sopsFile
    then sopswardenLib.mkSecretAccessors {
      inherit config;
      secrets = cfg.secrets;
    }
    else builtins.mapAttrs (name: _: "/run/secrets/${name}") cfg.secrets;

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

    # SOPS secrets configuration - conditionally set based on file existence
    # Use try-catch pattern since pathExists may not work reliably with flake paths
    (mkIf (cfg.secrets != {}) (
      let
        fileExists = builtins.pathExists cfg.sopsFile;
      in mkIf fileExists {
        sops.defaultSopsFile = cfg.sopsFile;
        sops.secrets = sopsSecrets;
      }
    ))

    # Package installation
    (mkIf cfg.installPackages {
      environment.systemPackages = sopswardenLib.defaultPackages pkgs;
    })

    # Sync command installation  
    (mkIf cfg.installSyncCommand {
      environment.systemPackages = [ syncScript ];
    })


    # Warnings for missing secrets file
    {
      warnings = optional (!(builtins.pathExists cfg.sopsFile) && cfg.secrets != {})
        "⚠️  sopswarden: secrets.yaml not found at ${toString cfg.sopsFile}. Run 'sopswarden-sync' to create it.";

      # Note: Disabled assertion for now due to pathExists issues in flake context
      # TODO: Re-enable with better file existence detection
      assertions = [
        # {
        #   assertion = cfg.secrets == {} || (builtins.pathExists cfg.sopsFile);
        #   message = ''
        #     ❌ sopswarden: secrets.yaml not found at ${toString cfg.sopsFile}
        #     
        #     🔧 To fix this:
        #        1. Run: sopswarden-sync
        #        2. Then rebuild: sudo nixos-rebuild switch
        #        
        #     💡 If sopswarden-sync fails, check:
        #        - rbw is authenticated: rbw unlock
        #        - secrets.nix definitions are correct
        #        - .sops.yaml configuration is valid
        #        
        #     📖 For help: https://github.com/pfassina/sopswarden#troubleshooting
        #   '';
        # }
      ];
    }
  ]);
}