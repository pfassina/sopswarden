# Test fresh installation workflow
# Simulates a user installing sopswarden from scratch and configuring their first secrets

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> {};
  
  # Simulate a fresh NixOS configuration with sopswarden
  freshInstallConfig = { config, pkgs, ... }: {
    imports = [ flake.nixosModules.default ];
    
    # Required for NixOS system evaluation
    system.stateVersion = "25.11";
    
    # User's first sopswarden configuration
    services.sopswarden = {
      enable = true;
      
      # Define some initial secrets
      secrets = {
        # Simple secret
        wifi-password = "Home WiFi";
        
        # Complex secret with user disambiguation
        api-key = {
          name = "My Service API";
          user = "admin@example.com";
          type = "login";
          field = "password";
        };
        
        # Note-type secret
        ssh-key = {
          name = "Server SSH Key";
          type = "note";
          field = "notes";
        };
      };
      
      # Use default settings for first install
      secretsFile = "/etc/nixos/secrets.nix";
      sopsFile = "/etc/nixos/secrets.yaml";
      ageKeyFile = "/root/.config/sops/age/keys.txt";
    };
    
    # Test that secrets are available in system config
    # This should work because sopswarden exports secrets via _module.args
    environment.etc."test-secret-access" = {
      text = "Secret paths created successfully";
    };
  };
  
  # Evaluate the configuration using nixosSystem for full module environment
  testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ freshInstallConfig ];
  };
  
  # Test results
  testResults = {
    # Basic module loading
    sopswardenEnabled = testSystem.config.services.sopswarden.enable;
    
    # Check secrets are properly configured
    hasSecrets = builtins.hasAttr "secrets" testSystem.config.services.sopswarden;
    secretCount = builtins.length (builtins.attrNames testSystem.config.services.sopswarden.secrets);
    
    # Verify SOPS integration
    hasSopsConfig = builtins.hasAttr "sops" testSystem.config;
    sopsDefaultFile = testSystem.config.sops.defaultSopsFile;
    
    # Check that all three secret types are configured
    hasWifiPassword = builtins.hasAttr "wifi-password" testSystem.config.services.sopswarden.secrets;
    hasApiKey = builtins.hasAttr "api-key" testSystem.config.services.sopswarden.secrets;
    hasSshKey = builtins.hasAttr "ssh-key" testSystem.config.services.sopswarden.secrets;
    
    # Verify secret normalization worked
    wifiSecret = testSystem.config.services.sopswarden.secrets.wifi-password;
    apiSecret = testSystem.config.services.sopswarden.secrets.api-key;
    sshSecret = testSystem.config.services.sopswarden.secrets.ssh-key;
    
    # Check package installation
    hasPackages = builtins.hasAttr "systemPackages" testSystem.config.environment;
    
    # Verify sync script is available
    installSyncCommand = testSystem.config.services.sopswarden.installSyncCommand;
  };

in {
  # Test fresh installation workflow
  freshInstall = testResults;
  
  # Validate the user journey works
  success = 
    testResults.sopswardenEnabled &&
    testResults.hasSecrets &&
    testResults.secretCount == 3 &&
    testResults.hasSopsConfig &&
    testResults.hasWifiPassword &&
    testResults.hasApiKey &&
    testResults.hasSshKey &&
    testResults.installSyncCommand;
    
  # Detailed validation
  validation = {
    canEnableSopswarden = testResults.sopswardenEnabled;
    allSecretsConfigured = testResults.secretCount == 3;
    sopsIntegrationWorks = testResults.hasSopsConfig;
    secretTypesWork = testResults.hasWifiPassword && testResults.hasApiKey && testResults.hasSshKey;
    packagesInstalled = testResults.hasPackages;
  };
}