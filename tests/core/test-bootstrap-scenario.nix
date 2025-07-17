# Test bootstrap scenario where no sopswarden files exist yet
# This test ensures the system can build successfully on first install

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> { };

  # Configuration for a fresh system with no existing sopswarden files
  bootstrapConfig = { ... }: {
    imports = [ flake.nixosModules.default ];

    # Required for NixOS system evaluation
    system.stateVersion = "25.11";

    # Enable sopswarden with non-existent files
    services.sopswarden = {
      enable = true;
      
      # These files don't exist on fresh install - use unique paths that definitely don't exist
      sopsFile = "/tmp/sopswarden-bootstrap-test-${builtins.toString builtins.currentTime}/secrets.yaml";
      sopsConfigFile = "/tmp/sopswarden-bootstrap-test-${builtins.toString builtins.currentTime}/.sops.yaml";
      hashFile = "/tmp/sopswarden-bootstrap-test-${builtins.toString builtins.currentTime}/.last-sync-hash";
      
      # Define some secrets
      secrets = {
        wifi-password = "Home WiFi";
        api-key = { name = "Service API"; field = "api_key"; };
        db-password = { name = "Database"; user = "admin@example.com"; };
      };
    };
  };

  # Evaluate the system configuration
  testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ bootstrapConfig ];
  };

  # Helper to safely check if evaluation succeeded
  evaluationSucceeded = builtins.tryEval (testSystem.config.services.sopswarden.enable);

  # Test that sopswarden is enabled
  sopswardenEnabled = 
    if evaluationSucceeded.success
    then testSystem.config.services.sopswarden.enable
    else false;

  # Test that sopswarden-sync is available in system packages
  hasSopswardenSync = 
    if evaluationSucceeded.success
    then builtins.any 
      (pkg: 
        let pkgCheck = builtins.tryEval (builtins.hasAttr "name" pkg && pkg.name == "sopswarden-sync");
        in pkgCheck.success && pkgCheck.value
      )
      testSystem.config.environment.systemPackages
    else false;

  # Test that warnings are generated for bootstrap
  hasBootstrapWarning =
    if evaluationSucceeded.success
    then builtins.any
      (warning: builtins.match ".*No secrets file found.*" warning != null)
      (testSystem.config.warnings or [])
    else false;

  # Test that SOPS is not configured when files don't exist
  sopsNotConfigured =
    if evaluationSucceeded.success
    then 
      let sopsFileCheck = builtins.tryEval testSystem.config.sops.defaultSopsFile;
      in !sopsFileCheck.success
    else true;

  # Test that secrets accessor is still exported (returns paths)
  hasSecretAccessors =
    if evaluationSucceeded.success
    then builtins.hasAttr "secrets" testSystem._module.args
    else false;

  # Test that activation script is created
  hasActivationScript =
    if evaluationSucceeded.success
    then builtins.hasAttr "sopswarden-setup" testSystem.config.system.activationScripts
    else false;

in
{
  # Test that the system can be evaluated without the files existing
  canEvaluateWithoutFiles = evaluationSucceeded.success;

  # Export individual test results
  inherit sopswardenEnabled hasSopswardenSync hasBootstrapWarning sopsNotConfigured hasSecretAccessors hasActivationScript;

  # Overall test success  
  success = 
    evaluationSucceeded.success &&
    sopswardenEnabled &&
    hasSopswardenSync &&
    hasBootstrapWarning &&
    sopsNotConfigured;

  # Detailed results for debugging
  details = {
    evaluationResult = evaluationSucceeded;
    warnings = if evaluationSucceeded.success then testSystem.config.warnings or [] else [];
  };
}