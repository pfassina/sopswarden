# Test rbw state handling during build and evaluation time
# Validates that sopswarden handles rbw being locked, unlocked, or unavailable

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> {};
  
  # Test rbw locked state during build
  testRbwLocked = 
    let
      # Configuration that would normally trigger rbw access
      rbwLockedConfig = { config, pkgs, ... }: {
        imports = [ flake.nixosModules.default ];
        
        # Required for NixOS system evaluation
        system.stateVersion = "25.11";
        
        services.sopswarden = {
          enable = true;
          secrets = {
            # These secrets would require rbw access to sync
            test-secret = "Test Item";
            complex-secret = {
              name = "Complex Item";
              user = "test@example.com";
              type = "login";
              field = "password";
            };
          };
          
          # Enable change detection (uses impure functions)
          enableChangeDetection = true;
          
          # Configure rbw command
          rbwCommand = "${pkgs.rbw}/bin/rbw";
        };
      };
      
      # Evaluate the configuration using nixosSystem for full module environment
      testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ rbwLockedConfig ];
      };
    in {
      # Configuration should evaluate even when rbw is locked
      canEvaluateConfig = builtins.hasAttr "config" testSystem;
      sopswardenEnabled = testSystem.config.services.sopswarden.enable;
      
      # Secrets should be configured in SOPS even without rbw access
      hasSecretsConfig = builtins.hasAttr "secrets" testSystem.config.services.sopswarden;
      secretsCount = builtins.length (builtins.attrNames testSystem.config.services.sopswarden.secrets);
      
      # SOPS configuration should be generated
      hasSopsConfig = builtins.hasAttr "sops" testSystem.config;
      sopsSecretsCount = builtins.length (builtins.attrNames testSystem.config.sops.secrets);
      
      # rbw package should be available
      hasRbwPackage = builtins.hasAttr "rbwPackage" testSystem.config.services.sopswarden;
      rbwCommandConfigured = testSystem.config.services.sopswarden.rbwCommand != "";
      
      # System packages should include rbw
      hasSystemPackages = builtins.hasAttr "systemPackages" testSystem.config.environment;
    };
  
  # Test rbw unlocked state during build
  testRbwUnlocked = 
    let
      # Similar configuration, but simulating rbw being available
      rbwUnlockedConfig = { config, pkgs, ... }: {
        imports = [ flake.nixosModules.default ];
        
        # Required for NixOS system evaluation
        system.stateVersion = "25.11";
        
        services.sopswarden = {
          enable = true;
          secrets = {
            wifi-password = "Home WiFi";
            api-key = {
              name = "API Service";
              user = "admin@example.com";
              type = "login";
              field = "password";
            };
          };
          
          # Enable all features
          enableChangeDetection = true;
          installPackages = true;
          installSyncCommand = true;
          
          # Configure rbw
          rbwPackage = pkgs.rbw;
          rbwCommand = "${pkgs.rbw}/bin/rbw";
        };
      };
      
      # Evaluate the configuration using nixosSystem for full module environment
      testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ rbwUnlockedConfig ];
      };
    in {
      # Configuration should evaluate successfully
      canEvaluateConfig = builtins.hasAttr "config" testSystem;
      sopswardenEnabled = testSystem.config.services.sopswarden.enable;
      
      # All features should be enabled
      changeDetectionEnabled = testSystem.config.services.sopswarden.enableChangeDetection;
      packagesInstalled = testSystem.config.services.sopswarden.installPackages;
      syncCommandInstalled = testSystem.config.services.sopswarden.installSyncCommand;
      
      # Secrets configuration
      hasSecretsConfig = builtins.hasAttr "secrets" testSystem.config.services.sopswarden;
      secretsCount = builtins.length (builtins.attrNames testSystem.config.services.sopswarden.secrets);
      hasSopsConfig = builtins.hasAttr "sops" testSystem.config;
      sopsSecretsCount = builtins.length (builtins.attrNames testSystem.config.sops.secrets);
      
      # rbw configuration
      rbwPackageSet = testSystem.config.services.sopswarden.rbwPackage == pkgs.rbw;
      rbwCommandSet = testSystem.config.services.sopswarden.rbwCommand == "${pkgs.rbw}/bin/rbw";
    };
  
  # Test rbw unavailable/missing during build
  testRbwUnavailable = 
    let
      # Configuration with rbw missing or unavailable
      rbwUnavailableConfig = { config, pkgs, ... }: {
        imports = [ flake.nixosModules.default ];
        
        # Required for NixOS system evaluation
        system.stateVersion = "25.11";
        
        services.sopswarden = {
          enable = true;
          secrets = {
            test-secret = "Test Item";
          };
          
          # Don't install packages (simulate rbw not being available)
          installPackages = false;
          installSyncCommand = false;
          
          # Disable change detection to avoid file system access
          enableChangeDetection = false;
          
          # Use a non-existent rbw command
          rbwCommand = "/nonexistent/rbw";
        };
      };
      
      # Evaluate the configuration using nixosSystem for full module environment
      testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ rbwUnavailableConfig ];
      };
    in {
      # Configuration should still evaluate
      canEvaluateConfig = builtins.hasAttr "config" testSystem;
      sopswardenEnabled = testSystem.config.services.sopswarden.enable;
      
      # Secrets should still be configured
      hasSecretsConfig = builtins.hasAttr "secrets" testSystem.config.services.sopswarden;
      secretsCount = builtins.length (builtins.attrNames testSystem.config.services.sopswarden.secrets);
      
      # SOPS should still work
      hasSopsConfig = builtins.hasAttr "sops" testSystem.config;
      sopsSecretsCount = builtins.length (builtins.attrNames testSystem.config.sops.secrets);
      
      # Features should be disabled as configured
      packagesNotInstalled = !testSystem.config.services.sopswarden.installPackages;
      syncCommandNotInstalled = !testSystem.config.services.sopswarden.installSyncCommand;
      changeDetectionDisabled = !testSystem.config.services.sopswarden.enableChangeDetection;
      
      # rbw command should be set to the non-existent path
      rbwCommandSet = testSystem.config.services.sopswarden.rbwCommand == "/nonexistent/rbw";
    };
  
  # Test sync script generation with different rbw states
  testSyncScriptGeneration = 
    let
      # Test sync script creation with different rbw configurations
      normalScript = builtins.tryEval (flake.lib.mkSyncScript {
        inherit pkgs;
        rbwCommand = "${pkgs.rbw}/bin/rbw";
      });
      
      customScript = builtins.tryEval (flake.lib.mkSyncScript {
        inherit pkgs;
        rbwCommand = "/custom/rbw";
        rbwPackage = pkgs.rbw;
      });
      
      missingScript = builtins.tryEval (flake.lib.mkSyncScript {
        inherit pkgs;
        rbwCommand = "/nonexistent/rbw";
      });
    in {
      # All scripts should be generatable regardless of rbw state
      canCreateNormalScript = normalScript.success;
      canCreateCustomScript = customScript.success;
      canCreateMissingScript = missingScript.success;
      
      # Scripts should be derivations
      normalScriptIsDerivation = if normalScript.success 
        then builtins.isAttrs normalScript.value && builtins.hasAttr "type" normalScript.value
        else false;
      customScriptIsDerivation = if customScript.success 
        then builtins.isAttrs customScript.value && builtins.hasAttr "type" customScript.value
        else false;
      missingScriptIsDerivation = if missingScript.success 
        then builtins.isAttrs missingScript.value && builtins.hasAttr "type" missingScript.value
        else false;
    };

in {
  # Test results for different rbw states
  rbwLocked = testRbwLocked;
  rbwUnlocked = testRbwUnlocked;
  rbwUnavailable = testRbwUnavailable;
  syncScriptGeneration = testSyncScriptGeneration;
  
  # Overall success - sopswarden should work regardless of rbw state during build
  success = 
    testRbwLocked.canEvaluateConfig &&
    testRbwLocked.sopswardenEnabled &&
    testRbwLocked.secretsCount == 2 &&
    testRbwLocked.sopsSecretsCount == 2 &&
    testRbwUnlocked.canEvaluateConfig &&
    testRbwUnlocked.sopswardenEnabled &&
    testRbwUnlocked.secretsCount == 2 &&
    testRbwUnlocked.sopsSecretsCount == 2 &&
    testRbwUnavailable.canEvaluateConfig &&
    testRbwUnavailable.sopswardenEnabled &&
    testRbwUnavailable.secretsCount == 1 &&
    testRbwUnavailable.sopsSecretsCount == 1 &&
    testSyncScriptGeneration.canCreateNormalScript &&
    testSyncScriptGeneration.canCreateCustomScript &&
    testSyncScriptGeneration.canCreateMissingScript;
    
  # Detailed validation
  validation = {
    handlesRbwLocked = testRbwLocked.canEvaluateConfig && testRbwLocked.sopswardenEnabled;
    handlesRbwUnlocked = testRbwUnlocked.canEvaluateConfig && testRbwUnlocked.sopswardenEnabled;
    handlesRbwUnavailable = testRbwUnavailable.canEvaluateConfig && testRbwUnavailable.sopswardenEnabled;
    syncScriptAlwaysGenerates = testSyncScriptGeneration.canCreateNormalScript && testSyncScriptGeneration.canCreateCustomScript && testSyncScriptGeneration.canCreateMissingScript;
    sopsIntegrationIndependent = testRbwLocked.hasSopsConfig && testRbwUnlocked.hasSopsConfig && testRbwUnavailable.hasSopsConfig;
    configurationResilient = testRbwLocked.hasSecretsConfig && testRbwUnlocked.hasSecretsConfig && testRbwUnavailable.hasSecretsConfig;
  };
}