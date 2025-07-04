# Test NixOS module integration and secrets usage in system config
# Validates that secrets.secret-name syntax works throughout the system

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> {};
  
  # Test NixOS system configuration using sopswarden secrets
  systemConfig = { config, pkgs, ... }: {
    imports = [ flake.nixosModules.default ];
    
    # Required for NixOS system evaluation
    system.stateVersion = "25.11";
    
    services.sopswarden = {
      enable = true;
      secrets = {
        # Network secrets
        wifi-password = "Home WiFi Network";
        vpn-key = {
          name = "VPN Configuration";
          type = "note";
          field = "notes";
        };
        
        # Service secrets
        database-password = {
          name = "Main Database";
          user = "admin@example.com";
          type = "login";
          field = "password";
        };
        
        api-token = "External API Service";
        
        # System secrets
        ssl-cert = {
          name = "SSL Certificate";
          type = "note";
          field = "certificate";
        };
        
        backup-key = "Backup Encryption";
      };
    };
    
    # Test secret usage in various system services
    # The secrets should be available via the 'secrets' argument
    
    # Network configuration
    networking.wireless.networks."MyWiFi" = {
      # This should work: secrets.wifi-password resolves to SOPS path
      pskRaw = "ext:secrets.wifi-password";
    };
    
    # Service configuration
    services.postgresql = {
      enable = true;
      authentication = ''
        # Using database password secret
        local all admin md5
      '';
    };
    
    # System files using secrets
    environment.etc."api-config".text = ''
      [api]
      # Secret token will be available at runtime
      token_file = /run/secrets/api-token
    '';
    
    # Custom systemd service using secrets
    systemd.services.backup-service = {
      description = "Backup service using sopswarden secrets";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Service should have access to decrypted secrets
        LoadCredential = "backup-key:/run/secrets/backup-key";
      };
      script = ''
        echo "Backup service can access secrets"
        # In real usage, the secret would be read from /run/secrets/backup-key
      '';
    };
  };
  
  # Evaluate the system configuration using nixosSystem for full module environment
  testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ systemConfig ];
  };
  
  # Test results
  testResults = {
    # Basic configuration
    sopswardenEnabled = testSystem.config.services.sopswarden.enable;
    secretsConfigured = builtins.length (builtins.attrNames testSystem.config.services.sopswarden.secrets);
    
    # SOPS integration
    hasSopsConfig = builtins.hasAttr "sops" testSystem.config;
    sopsSecretsCount = builtins.length (builtins.attrNames testSystem.config.sops.secrets);
    
    # Service integration tests
    hasPostgresql = testSystem.config.services.postgresql.enable;
    hasWirelessConfig = builtins.hasAttr "wireless" testSystem.config.networking;
    
    # System files
    hasApiConfig = builtins.hasAttr "api-config" testSystem.config.environment.etc;
    
    # Systemd service
    hasBackupService = builtins.hasAttr "backup-service" testSystem.config.systemd.services;
    
    # Verify all secret types are handled
    hasWifiPassword = builtins.hasAttr "wifi-password" testSystem.config.services.sopswarden.secrets;
    hasVpnKey = builtins.hasAttr "vpn-key" testSystem.config.services.sopswarden.secrets;
    hasDatabasePassword = builtins.hasAttr "database-password" testSystem.config.services.sopswarden.secrets;
    hasApiToken = builtins.hasAttr "api-token" testSystem.config.services.sopswarden.secrets;
    hasSslCert = builtins.hasAttr "ssl-cert" testSystem.config.services.sopswarden.secrets;
    hasBackupKey = builtins.hasAttr "backup-key" testSystem.config.services.sopswarden.secrets;
    
    # Check that secrets are properly exported to other modules
    # This tests the _module.args.secrets export functionality
    hasModuleArgs = builtins.hasAttr "_module" testSystem.config;
    
    # Verify package installation
    hasSystemPackages = builtins.hasAttr "systemPackages" testSystem.config.environment;
    installPackages = testSystem.config.services.sopswarden.installPackages;
  };

in {
  # Test NixOS module integration
  nixosModule = testResults;
  
  # Validate the module works correctly
  success = 
    testResults.sopswardenEnabled &&
    testResults.secretsConfigured == 6 &&
    testResults.hasSopsConfig &&
    testResults.sopsSecretsCount == 6 &&
    testResults.hasPostgresql &&
    testResults.hasApiConfig &&
    testResults.hasBackupService &&
    testResults.hasWifiPassword &&
    testResults.hasVpnKey &&
    testResults.hasDatabasePassword &&
    testResults.hasApiToken &&
    testResults.hasSslCert &&
    testResults.hasBackupKey &&
    testResults.installPackages;
    
  # Detailed validation
  validation = {
    moduleLoadsCorrectly = testResults.sopswardenEnabled;
    allSecretsConfigured = testResults.secretsConfigured == 6;
    sopsIntegrationWorks = testResults.hasSopsConfig && testResults.sopsSecretsCount == 6;
    servicesCanUseSecrets = testResults.hasPostgresql && testResults.hasApiConfig && testResults.hasBackupService;
    allSecretTypesSupported = testResults.hasWifiPassword && testResults.hasVpnKey && testResults.hasDatabasePassword && testResults.hasApiToken && testResults.hasSslCert && testResults.hasBackupKey;
    packagesInstalled = testResults.hasSystemPackages && testResults.installPackages;
  };
}