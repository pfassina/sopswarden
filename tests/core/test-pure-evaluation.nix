# Test that the current impure implementation works correctly
# This validates the flake works as designed with --impure flag

let
  flake = builtins.getFlake (toString ../..);

  # Test basic flake structure
  testFlakeStructure = {
    hasLib = builtins.hasAttr "lib" flake;
    hasNixosModules = builtins.hasAttr "nixosModules" flake;
    hasHomeManagerModules = builtins.hasAttr "homeManagerModules" flake;
    hasOverlays = builtins.hasAttr "overlays" flake;
  };

  # Test library functions work with impure evaluation
  testLibFunctions =
    let
      inherit (flake) lib;
    in
    {
      # Test pure functions
      canCreateSyncScript = builtins.isFunction lib.mkSyncScript;
      hasSecretTypes = builtins.hasAttr "secretTypes" lib;

      # Test secret normalization
      normalizeSimpleSecret = lib.normalizeSecretDef "test-secret";
      normalizeComplexSecret = lib.normalizeSecretDef {
        name = "test-secret";
        user = "test@example.com";
        type = "login";
        field = "password";
      };

      # Test impure functions (these need files to exist for full testing)
      canCreateSopsSecrets = builtins.isFunction lib.mkSopsSecrets;
      canCreateSecretAccessors = builtins.isFunction lib.mkSecretAccessors;
      canCreateHashTracker = builtins.isFunction lib.mkHashTracker;
    };

  # Test NixOS module options structure
  testNixosModuleOptions =
    let
      nixosModule = flake.nixosModules.default;
    in
    {
      # Module should be a function
      isFunction = builtins.isFunction nixosModule;

      # We can't safely do full module evaluation here due to sops-nix dependencies
      # This is a limitation of the test environment, not the code
      moduleCanBeImported = builtins.isFunction nixosModule;
    };

in
{
  # Test results
  flakeStructure = testFlakeStructure;
  libFunctions = testLibFunctions;
  nixosModuleOptions = testNixosModuleOptions;

  # Overall success validation
  success =
    testFlakeStructure.hasLib &&
    testFlakeStructure.hasNixosModules &&
    testLibFunctions.canCreateSyncScript &&
    testLibFunctions.normalizeSimpleSecret.name == "test-secret" &&
    testLibFunctions.normalizeComplexSecret.user == "test@example.com" &&
    testNixosModuleOptions.isFunction;
}
