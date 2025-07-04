# Test mkSopsSecrets function - validates SOPS configuration generation
# Tests that the function properly handles sopsFile parameter and creates correct SOPS configurations

let
  flake = builtins.getFlake (toString ../..);

  # Test that function exists and can be called
  testBasicFunctionality =
    let
      # Test with minimal parameters
      minimalTest = builtins.tryEval (flake.lib.mkSopsSecrets {
        secrets = { };
        sopsFile = "/test/secrets.yaml";
      });

      minimalResult = if minimalTest.success then minimalTest.value else { };
    in
    {
      # Test function existence
      canCallFunction = builtins.isFunction flake.lib.mkSopsSecrets;

      minimalWorks = minimalTest.success;
      minimalIsEmpty = builtins.length (builtins.attrNames minimalResult) == 0;
    };

  # Test with actual secrets and custom sopsFile
  testSopsFileParameter =
    let
      # Test with secrets and custom sopsFile
      customSopsTest = builtins.tryEval (flake.lib.mkSopsSecrets {
        secrets = {
          test-secret = { name = "Test"; };
          another-secret = { name = "Another"; };
        };
        sopsFile = "/custom/path/secrets.yaml";
        defaultOwner = "testuser";
        defaultGroup = "testgroup";
        defaultMode = "0600";
      });

      customResult = if customSopsTest.success then customSopsTest.value else { };

      # Test with different sopsFile
      altSopsTest = builtins.tryEval (flake.lib.mkSopsSecrets {
        secrets = {
          test-secret = { name = "Test"; };
        };
        sopsFile = "/alternative/secrets.yaml";
      });

      altResult = if altSopsTest.success then altSopsTest.value else { };
    in
    {
      # Test function calls
      customSopsWorks = customSopsTest.success;
      altSopsWorks = altSopsTest.success;

      # Test results structure
      customHasSecrets = builtins.hasAttr "test-secret" customResult && builtins.hasAttr "another-secret" customResult;
      altHasSecret = builtins.hasAttr "test-secret" altResult;

      # Test that sopsFile is properly set (this was the bug)
      customSopsFileCorrect =
        if customSopsTest.success && builtins.hasAttr "test-secret" customResult
        then customResult.test-secret.sopsFile == "/custom/path/secrets.yaml"
        else false;
      altSopsFileCorrect =
        if altSopsTest.success && builtins.hasAttr "test-secret" altResult
        then altResult.test-secret.sopsFile == "/alternative/secrets.yaml"
        else false;

      # Test other parameters
      customOwnerCorrect =
        if customSopsTest.success && builtins.hasAttr "test-secret" customResult
        then customResult.test-secret.owner == "testuser"
        else false;
      customGroupCorrect =
        if customSopsTest.success && builtins.hasAttr "test-secret" customResult
        then customResult.test-secret.group == "testgroup"
        else false;
      customModeCorrect =
        if customSopsTest.success && builtins.hasAttr "test-secret" customResult
        then customResult.test-secret.mode == "0600"
        else false;

      # Test secret count
      customSecretCount = builtins.length (builtins.attrNames customResult);
      altSecretCount = builtins.length (builtins.attrNames altResult);
    };

  # Test default parameters
  testDefaultParameters =
    let
      defaultTest = builtins.tryEval (flake.lib.mkSopsSecrets {
        secrets = {
          default-secret = { name = "Default"; };
        };
        # Using default sopsFile = ./secrets.yaml
      });

      defaultResult = if defaultTest.success then defaultTest.value else { };
    in
    {
      defaultWorks = defaultTest.success;
      hasDefaultSecret = builtins.hasAttr "default-secret" defaultResult;

      # Test default values
      defaultOwnerCorrect =
        if defaultTest.success && builtins.hasAttr "default-secret" defaultResult
        then defaultResult.default-secret.owner == "root"
        else false;
      defaultGroupCorrect =
        if defaultTest.success && builtins.hasAttr "default-secret" defaultResult
        then defaultResult.default-secret.group == "root"
        else false;
      defaultModeCorrect =
        if defaultTest.success && builtins.hasAttr "default-secret" defaultResult
        then defaultResult.default-secret.mode == "0400"
        else false;
    };

in
{
  # Test results
  basicFunctionality = testBasicFunctionality;
  sopsFileParameter = testSopsFileParameter;
  defaultParameters = testDefaultParameters;

  # Overall success validation - now testing the fix
  success =
    testBasicFunctionality.canCallFunction &&
    testBasicFunctionality.minimalWorks &&
    testBasicFunctionality.minimalIsEmpty &&
    testSopsFileParameter.customSopsWorks &&
    testSopsFileParameter.altSopsWorks &&
    testSopsFileParameter.customHasSecrets &&
    testSopsFileParameter.altHasSecret &&
    testSopsFileParameter.customSopsFileCorrect &&
    testSopsFileParameter.altSopsFileCorrect &&
    testSopsFileParameter.customOwnerCorrect &&
    testSopsFileParameter.customGroupCorrect &&
    testSopsFileParameter.customModeCorrect &&
    testSopsFileParameter.customSecretCount == 2 &&
    testSopsFileParameter.altSecretCount == 1 &&
    testDefaultParameters.defaultWorks &&
    testDefaultParameters.hasDefaultSecret &&
    testDefaultParameters.defaultOwnerCorrect &&
    testDefaultParameters.defaultGroupCorrect &&
    testDefaultParameters.defaultModeCorrect;

  # Detailed validation
  validation = {
    functionExists = testBasicFunctionality.canCallFunction;
    canCallWithEmptySecrets = testBasicFunctionality.minimalWorks;
    emptySecretsWork = testBasicFunctionality.minimalIsEmpty;
    sopsFileParameterWorks = testSopsFileParameter.customSopsFileCorrect && testSopsFileParameter.altSopsFileCorrect;
    customParametersWork = testSopsFileParameter.customOwnerCorrect && testSopsFileParameter.customGroupCorrect && testSopsFileParameter.customModeCorrect;
    defaultParametersWork = testDefaultParameters.defaultOwnerCorrect && testDefaultParameters.defaultGroupCorrect && testDefaultParameters.defaultModeCorrect;
    multipleSecretsWork = testSopsFileParameter.customSecretCount == 2;
    bugIsFixed = testSopsFileParameter.customSopsFileCorrect && testSopsFileParameter.altSopsFileCorrect;
  };
}
