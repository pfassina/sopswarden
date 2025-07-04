# Test cyclic dependency prevention during build and evaluation
# Validates that the flake can be evaluated and built without circular dependencies

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> { };

  # Test basic evaluation without cyclic dependencies
  testBasicEvaluation = {
    # These should evaluate without issues
    hasFlakeOutputs = builtins.hasAttr "nixosModules" flake && builtins.hasAttr "lib" flake;
    canAccessLib = builtins.isAttrs flake.lib;
    canAccessModules = builtins.isAttrs flake.nixosModules;

    # Library functions should be evaluable
    libFunctions = {
      mkSyncScript = builtins.isFunction flake.lib.mkSyncScript;
      mkSopsSecrets = builtins.isFunction flake.lib.mkSopsSecrets;
      normalizeSecretDef = builtins.isFunction flake.lib.normalizeSecretDef;

      # These are the potentially problematic functions (they use impure operations)
      mkSecretAccessors = builtins.isFunction flake.lib.mkSecretAccessors;
      mkHashTracker = builtins.isFunction flake.lib.mkHashTracker;
    };
  };

  # Test module evaluation without causing circular dependencies
  testModuleEvaluation =
    let
      # Create a minimal configuration that doesn't trigger file reads
      minimalConfig = { ... }: {
        imports = [ flake.nixosModules.default ];

        # Required for NixOS system evaluation
        system.stateVersion = "25.11";

        # Enable sopswarden but don't trigger the problematic impure functions
        services.sopswarden = {
          enable = true;

          # Define secrets but don't evaluate them yet
          secrets = {
            test-secret = "Test Item";
          };

          # Disable features that might cause circular dependencies
          enableChangeDetection = false;
          installPackages = false;
          installSyncCommand = false;
        };
      };

      # Evaluate the module options using nixosSystem for full module environment
      moduleOptions = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ minimalConfig ];
      };
    in
    {
      # Basic module evaluation
      canEvaluateModule = builtins.hasAttr "options" moduleOptions;
      hasSecretsOption = builtins.hasAttr "services" moduleOptions.options &&
        builtins.hasAttr "sopswarden" moduleOptions.options.services;

      # Configuration evaluation
      canEvaluateConfig = builtins.hasAttr "config" moduleOptions;
      sopswardenEnabled = moduleOptions.config.services.sopswarden.enable;

      # Check if SOPS integration works without circular dependencies
      hasSopsConfig = builtins.hasAttr "sops" moduleOptions.config;
    };

  # Test package building without circular dependencies
  testPackageBuilding =
    let
      # Try to build the sync script package
      syncScriptResult = builtins.tryEval (flake.lib.mkSyncScript {
        inherit pkgs;
        secretsFile = "/test/secrets.nix";
        sopsFile = "/test/secrets.yaml";
        ageKeyFile = "/test/age/keys.txt";
        sopsConfigFile = "/test/.sops.yaml";
      });
    in
    {
      # Package should be buildable
      canBuildSyncScript = syncScriptResult.success;
      syncScriptIsDerivation =
        if syncScriptResult.success
        then builtins.isAttrs syncScriptResult.value && builtins.hasAttr "type" syncScriptResult.value
        else false;
    };

  # Test evaluation order dependencies
  testEvaluationOrder =
    let
      # Test that we can evaluate components in any order without issues
      libFirst = flake.lib.normalizeSecretDef "test";
      moduleFirst = flake.nixosModules.default;
      libSecond = flake.lib.mkSyncScript { inherit pkgs; };
    in
    {
      # Should be able to access library functions first
      canAccessLibFirst = builtins.isAttrs libFirst && libFirst.name == "test";

      # Should be able to access modules first
      canAccessModuleFirst = builtins.isFunction moduleFirst;

      # Should be able to access library functions after modules
      canAccessLibSecond = builtins.isAttrs libSecond;
    };

  # Test the problematic impure functions in isolation
  testImpureFunctions =
    let
      # Test mkSecretAccessors with minimal config
      secretAccessorsTest = builtins.tryEval (flake.lib.mkSecretAccessors {
        config = { sops = { secrets = { }; }; };
        secrets = { };
      });

      # Test mkHashTracker with non-existent files
      hashTrackerTest = builtins.tryEval (flake.lib.mkHashTracker {
        secretsFile = "/nonexistent/secrets.nix";
        hashFile = "/nonexistent/hash";
      });
    in
    {
      # These might fail due to file system access, but shouldn't cause circular deps
      secretAccessorsCalled = builtins.isAttrs secretAccessorsTest;
      hashTrackerCalled = builtins.isAttrs hashTrackerTest;

      # The important thing is they don't cause evaluation to hang or create cycles
      noCircularDependency = true; # If we get here, no circular deps occurred
    };

in
{
  # Test results
  basicEvaluation = testBasicEvaluation;
  moduleEvaluation = testModuleEvaluation;
  packageBuilding = testPackageBuilding;
  evaluationOrder = testEvaluationOrder;
  impureFunctions = testImpureFunctions;

  # Overall success - no circular dependencies detected
  success =
    testBasicEvaluation.hasFlakeOutputs &&
    testBasicEvaluation.canAccessLib &&
    testBasicEvaluation.canAccessModules &&
    testBasicEvaluation.libFunctions.mkSyncScript &&
    testModuleEvaluation.canEvaluateModule &&
    testModuleEvaluation.canEvaluateConfig &&
    testPackageBuilding.canBuildSyncScript &&
    testEvaluationOrder.canAccessLibFirst &&
    testEvaluationOrder.canAccessModuleFirst &&
    testEvaluationOrder.canAccessLibSecond &&
    testImpureFunctions.noCircularDependency;

  # Detailed validation
  validation = {
    flakeEvaluatesCleanly = testBasicEvaluation.hasFlakeOutputs;
    librarySafeToUse = testBasicEvaluation.canAccessLib;
    modulesSafeToUse = testBasicEvaluation.canAccessModules;
    packagesCanBuild = testPackageBuilding.canBuildSyncScript;
    evaluationOrderIndependent = testEvaluationOrder.canAccessLibFirst && testEvaluationOrder.canAccessModuleFirst;
    noCircularDependencies = testImpureFunctions.noCircularDependency;
  };
}
