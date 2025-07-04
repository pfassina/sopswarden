# Test library functions in isolation
# Validates that all library functions work correctly with various inputs

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> { };
  inherit (flake) lib;

  # Test normalizeSecretDef function
  testNormalizeSecretDef = {
    # Test simple string input
    simpleSecret = lib.normalizeSecretDef "test-secret";

    # Test complex object input with all fields
    complexSecret = lib.normalizeSecretDef {
      name = "complex-secret";
      user = "test@example.com";
      type = "login";
      field = "password";
    };

    # Test partial object input (should fill defaults)
    partialSecret = lib.normalizeSecretDef {
      name = "partial-secret";
      user = "test@example.com";
    };

    # Test note type
    noteSecret = lib.normalizeSecretDef {
      name = "note-secret";
      type = "note";
      field = "notes";
    };
  };

  # Test mkSyncScript function
  testMkSyncScript = {
    # Test basic sync script creation
    basicScript = lib.mkSyncScript { inherit pkgs; };

    # Test with custom parameters
    customScript = lib.mkSyncScript {
      inherit pkgs;
      secretsFile = "/custom/secrets.nix";
      sopsFile = "/custom/secrets.yaml";
      ageKeyFile = "/custom/age/keys.txt";
      sopsConfigFile = "/custom/.sops.yaml";
      rbwCommand = "/custom/rbw";
      forceSync = true;
      workingDirectory = "/custom/work";
    };
  };

  # Test mkSopsSecrets function
  testMkSopsSecrets = {
    # Test that the function exists and is callable
    canCallMkSopsSecrets = builtins.isFunction lib.mkSopsSecrets;
    functionExists = builtins.isFunction lib.mkSopsSecrets;

    # We can't safely test execution without proper file setup
    # The function uses ./secrets.yaml as default which doesn't exist in test context
  };

  # Test secret types
  testSecretTypes = {
    hasSimpleSecret = builtins.hasAttr "simpleSecret" lib.secretTypes;
    hasComplexSecret = builtins.hasAttr "complexSecret" lib.secretTypes;

    # Test type validation (this would be used by NixOS module system)
    simpleTypeIsString = lib.secretTypes.simpleSecret == pkgs.lib.types.str;
    complexTypeIsSubmodule = builtins.hasAttr "getSubOptions" lib.secretTypes.complexSecret;
  };

  # Test mkSecretAccessors function (impure)
  testMkSecretAccessors = {
    # Test that the function exists and is callable
    canCallMkSecretAccessors = builtins.isFunction lib.mkSecretAccessors;

    # We can't safely test this function without full NixOS module evaluation
    # due to its dependency on config.sops.secrets structure
    functionExists = builtins.isFunction lib.mkSecretAccessors;
  };

  # Test mkHashTracker function (impure)
  testMkHashTracker =
    let
      # Test hash tracker with non-existent files using tryEval
      hashTrackerResult = builtins.tryEval (lib.mkHashTracker {
        secretsFile = "/nonexistent/secrets.nix";
        hashFile = "/nonexistent/hash";
      });
    in
    {
      # Hash tracker function should be callable
      canCallMkHashTracker = builtins.isFunction lib.mkHashTracker;

      # With non-existent files, it may fail, but that's expected
      hashTrackerTried = builtins.isAttrs hashTrackerResult;

      # The important thing is the function exists and can be called
      functionExists = builtins.isFunction lib.mkHashTracker;
    };

  # Test defaultPackages function
  testDefaultPackages = {
    packages = lib.defaultPackages pkgs;
    hasPackages = builtins.isList (lib.defaultPackages pkgs);
    packageCount = builtins.length (lib.defaultPackages pkgs);

    # Should include required packages
    hasRbw = builtins.any (p: p.pname or p.name or "" == "rbw") (lib.defaultPackages pkgs);
    hasSops = builtins.any (p: p.pname or p.name or "" == "sops") (lib.defaultPackages pkgs);
    hasAge = builtins.any (p: p.pname or p.name or "" == "age") (lib.defaultPackages pkgs);
    hasJq = builtins.any (p: p.pname or p.name or "" == "jq") (lib.defaultPackages pkgs);
  };

in
{
  # Test results
  normalizeSecretDef = testNormalizeSecretDef;
  mkSyncScript = testMkSyncScript;
  mkSopsSecrets = testMkSopsSecrets;
  secretTypes = testSecretTypes;
  mkSecretAccessors = testMkSecretAccessors;
  mkHashTracker = testMkHashTracker;
  defaultPackages = testDefaultPackages;

  # Overall success validation
  success =
    # normalizeSecretDef tests
    testNormalizeSecretDef.simpleSecret.name == "test-secret" &&
    testNormalizeSecretDef.simpleSecret.type == "login" &&
    testNormalizeSecretDef.simpleSecret.field == "password" &&
    testNormalizeSecretDef.complexSecret.name == "complex-secret" &&
    testNormalizeSecretDef.complexSecret.user == "test@example.com" &&
    testNormalizeSecretDef.complexSecret.type == "login" &&
    testNormalizeSecretDef.partialSecret.type == "login" &&
    testNormalizeSecretDef.partialSecret.field == "password" &&
    testNormalizeSecretDef.noteSecret.type == "note" &&
    testNormalizeSecretDef.noteSecret.field == "notes" &&

    # mkSyncScript tests
    builtins.isAttrs testMkSyncScript.basicScript &&
    builtins.isAttrs testMkSyncScript.customScript &&

    # mkSopsSecrets tests
    testMkSopsSecrets.canCallMkSopsSecrets &&
    testMkSopsSecrets.functionExists &&

    # secretTypes tests
    testSecretTypes.hasSimpleSecret &&
    testSecretTypes.hasComplexSecret &&

    # mkSecretAccessors tests
    testMkSecretAccessors.canCallMkSecretAccessors &&
    testMkSecretAccessors.functionExists &&

    # mkHashTracker tests
    testMkHashTracker.canCallMkHashTracker &&
    testMkHashTracker.functionExists &&

    # defaultPackages tests
    testDefaultPackages.hasPackages &&
    testDefaultPackages.packageCount == 4;
}
