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

  # Build the token → file map once for runtime substitution
  sopswardenHelpers = import ../lib/secret.nix { inherit lib; };
  secretNames = builtins.attrNames cfg.secrets;
  placeholders = builtins.listToAttrs (
    map (secretName: {
      name = sopswardenHelpers.mkSentinel secretName;  # "__SOPSWARDEN_GIT-USERNAME__"
      value = config.sops.secrets.${secretName}.path;   # "/run/secrets/git-username"
    }) secretNames
  );

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
        
        This is the canonical location for all sopswarden secrets.
        The bootstrap command and sync services will read/write this file.
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

    # Home Manager integration
    enableHmIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Add the rewrite hook to Home-Manager users when possible";
    };

    # Internal options for runtime substitution
    internal.placeholders = mkOption {
      type = types.attrsOf types.str;
      default = {};
      internal = true;
      description = "Internal mapping of sentinels to secret file paths for runtime substitution";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Always configure age and export secret accessors
    {
      # Note: Assertions with pathExists are commented out to allow pure evaluation
      # The boot service will guide users if files are missing at runtime
      # assertions = [
      #   {
      #     assertion = cfg.secrets == {} || builtins.pathExists absoluteSopsFile;
      #     message = ''
      #       sopswarden: secrets file is missing at ${absoluteSopsFile}
      #       
      #       To generate the encrypted secrets file:
      #       1. Unlock Bitwarden: rbw unlock
      #       2. Run bootstrap: nix run .#sopswarden-bootstrap
      #       3. Commit the file: git add ${absoluteSopsFile}
      #     '';
      #   }
      # ];

      sops = {
        defaultSopsFormat = "yaml";
        
        age = {
          keyFile = cfg.ageKeyFile;
          generateKey = true;
        };
      };

      # Export secrets and helpers for easy access in other modules
      _module.args = { 
        secrets = secretAccessors;
        sopswardenSecrets = secretAccessors; # Alternative name
        sopswarden = import ../lib/secret.nix { inherit lib; };
      };
    }

    # SOPS secrets configuration - always configure when secrets are defined
    (mkIf (cfg.secrets != {}) {
      sops.defaultSopsFile = absoluteSopsFile;
      sops.secrets = sopsSecrets;
      # Disable validation since we manage files externally via systemd services
      sops.validateSopsFiles = false;

      # Store the placeholders mapping for use by activation scripts
      services.sopswarden.internal.placeholders = placeholders;
    })

    # Runtime secret synchronization and validation
    (mkIf (cfg.secrets != {}) {
      # Create directory for sopswarden files
      systemd.tmpfiles.rules = [
        "d /var/lib/sopswarden 0755 ${cfg.defaultOwner} ${cfg.defaultGroup} -"
      ];

      # Allow user service to run without login session
      users.users.${cfg.defaultOwner}.linger = true;

      # Boot-time system service for updating secrets when needed
      systemd.services.sopswarden-sync-boot = {
        description = "Sopswarden: update secrets from Bitwarden if vault is unlocked";
        after = [ "network-online.target" ];
        before = [ "sops-nix.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "sops-nix.service" ];
        path = with pkgs; [ cfg.rbwPackage sops age ];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.defaultOwner;
          Group = cfg.defaultGroup;
          # Minimal environment - rbw never looks for agent socket
          Environment = [
            "HOME=${config.users.users.${cfg.defaultOwner}.home}"
            "XDG_CONFIG_HOME=${config.users.users.${cfg.defaultOwner}.home}/.config"
            "XDG_DATA_HOME=${config.users.users.${cfg.defaultOwner}.home}/.local/share"
            "XDG_RUNTIME_DIR=/tmp"
            "SOPS_FILE=${cfg.sopsFile}"
            "SOPS_CONFIG_FILE=${cfg.sopsConfigFile}"
            "AGE_KEY_FILE=${cfg.ageKeyFile}"
          ];
        };
        script = ''
          # Check if secrets file exists
          if [[ ! -f "${cfg.sopsFile}" ]]; then
            echo "❌ Secrets file missing: ${cfg.sopsFile}"
            echo ""
            echo "To generate the encrypted secrets file:"
            echo "  1. Unlock Bitwarden: rbw unlock"
            echo "  2. Run bootstrap: nix run .#sopswarden-bootstrap"
            echo "  3. Commit the file: git add ${cfg.sopsFile}"
            echo ""
            echo "Continuing without secrets sync (SOPS will fail if this is the first run)"
            exit 0
          fi
          
          # Check if rbw is already unlocked (from user session)
          if ${cfg.rbwPackage}/bin/rbw unlocked 2>/dev/null; then
            echo "🔄 rbw is unlocked, updating secrets from Bitwarden..."
            ${syncScript}/bin/sopswarden-sync
          else
            echo "🔒 rbw is locked, skipping sync (will use existing encrypted file)"
            echo "💡 Unlock rbw and run 'systemctl --user start sopswarden-sync' to update"
          fi
        '';
      };

      # User service to sync secrets from Bitwarden after user login
      systemd.user.services.sopswarden-sync = {
        description = "Fetch secrets from Bitwarden into SOPS file (user session)";
        after = [ "rbw-agent.socket" ];
        wants = [ "rbw-agent.socket" ];
        path = with pkgs; [ cfg.rbwPackage sops age ];
        environment = {
          SOPS_FILE = cfg.sopsFile;
          SOPS_CONFIG_FILE = cfg.sopsConfigFile;
          AGE_KEY_FILE = cfg.ageKeyFile;
        };
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          # Check if rbw is unlocked, skip if not
          if ! ${cfg.rbwPackage}/bin/rbw unlocked; then
            echo "🔒 rbw vault is locked - skipping sync"
            echo "💡 Run 'rbw unlock' to enable automatic sync"
            exit 0
          fi
          
          echo "🔄 Syncing secrets from Bitwarden..."
          ${syncScript}/bin/sopswarden-sync
        '';
        wantedBy = [ "default.target" ];
      };

      # User service to validate SOPS file after sync
      systemd.user.services.sopswarden-validate = {
        description = "Validate SOPS file after sync";
        path = with pkgs; [ sops ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          echo "🔍 Validating SOPS file: ${cfg.sopsFile}"
          if [[ -f "${cfg.sopsFile}" ]]; then
            sops --decrypt "${cfg.sopsFile}" > /dev/null
            echo "✅ SOPS file validation successful"
          else
            echo "⚠️  SOPS file not found: ${cfg.sopsFile}"
            echo "💡 Run 'systemctl --user start sopswarden-sync' to create the file"
            exit 1
          fi
        '';
        requires = [ "sopswarden-sync.service" ];
        after = [ "sopswarden-sync.service" ];
        wantedBy = [ "default.target" ];
      };

      # System-side substitution using helper script  
      system.activationScripts.sopswarden-rewrite = lib.stringAfter [ "specialfs" ]
        (import ../scripts/rewrite-system.nix {
          placeholders = cfg.internal.placeholders;
          inherit lib;
        });
    })

    # Home Manager integration - TODO: Implement automatic detection
    # For now, users need to manually import the Home Manager module
    # This ensures compatibility with systems that don't use Home Manager
    {}

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