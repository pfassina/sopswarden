# Updated unit tests for sopswarden library functions
{ pkgs ? import <nixpkgs> {} }:

let
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };
  
  # Mock config for testing mkSecretAccessors
  mockConfig = {
    sops.secrets = {
      test-secret = { path = "/run/secrets/test-secret"; };
      complex-secret = { path = "/run/secrets/complex-secret"; };
      note-secret = { path = "/run/secrets/note-secret"; };
    };
  };
  
  # Test normalizeSecretDef function
  testNormalizeSecretDef = {
    # Test simple string input
    simple = sopswardenLib.normalizeSecretDef "Test Item";
    expected_simple = {
      name = "Test Item";
      user = null;
      type = "login";
      field = "password";
    };
    
    # Test complex input with user
    complex = sopswardenLib.normalizeSecretDef {
      name = "Complex Item";
      user = "test@example.com";
    };
    expected_complex = {
      name = "Complex Item";
      user = "test@example.com";
      type = "login";
      field = "password";
    };
    
    # Test note input
    note = sopswardenLib.normalizeSecretDef {
      name = "Note Item";
      type = "note";
      field = "custom_field";
    };
    expected_note = {
      name = "Note Item";
      user = null;
      type = "note";
      field = "custom_field";
    };
    
    # Test with all fields
    complete = sopswardenLib.normalizeSecretDef {
      name = "Complete Item";
      user = "user@test.com";
      type = "note";
      field = "special_field";
    };
    expected_complete = {
      name = "Complete Item";
      user = "user@test.com";
      type = "note";
      field = "special_field";
    };
  };

  # Test mkSopsSecrets function
  testMkSopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = { 
      test-secret = "Test Item";
      another-secret = { name = "Another"; user = "test"; };
    };
    sopsFile = "/test/secrets.yaml";
    defaultOwner = "testuser";
    defaultGroup = "testgroup";
    defaultMode = "0440";
  };

  # Test mkSecretAccessors function (new pure version)
  testSecrets = {
    test-secret = "Test Item";
    complex-secret = { name = "Complex"; user = "test"; };
    note-secret = { name = "Note"; type = "note"; field = "field"; };
  };
  
  testSecretAccessors = sopswardenLib.mkSecretAccessors {
    config = mockConfig;
    secrets = testSecrets;
  };

  # Test mkSyncScript function
  testSyncScript = sopswardenLib.mkSyncScript {
    inherit pkgs;
    secrets = testSecrets;
    sopsFile = "/test/secrets.yaml";
    ageKeyFile = "/test/keys.txt";
    sopsConfigFile = "/test/.sops.yaml";
  };

  # Run assertions - check individual fields instead of full equality
  assertions = {
    # Test normalizeSecretDef results by checking individual fields
    simple = testNormalizeSecretDef.simple.name == "Test Item" &&
             testNormalizeSecretDef.simple.type == "login" &&
             testNormalizeSecretDef.simple.field == "password" &&
             testNormalizeSecretDef.simple.user == null;
             
    complex = testNormalizeSecretDef.complex.name == "Complex Item" &&
              testNormalizeSecretDef.complex.user == "test@example.com" &&
              testNormalizeSecretDef.complex.type == "login" &&
              testNormalizeSecretDef.complex.field == "password";
              
    note = testNormalizeSecretDef.note.name == "Note Item" &&
           testNormalizeSecretDef.note.type == "note" &&
           testNormalizeSecretDef.note.field == "custom_field" &&
           testNormalizeSecretDef.note.user == null;
           
    complete = testNormalizeSecretDef.complete.name == "Complete Item" &&
               testNormalizeSecretDef.complete.user == "user@test.com" &&
               testNormalizeSecretDef.complete.type == "note" &&
               testNormalizeSecretDef.complete.field == "special_field";
    
    sopsSecrets = testMkSopsSecrets ? test-secret && 
                  testMkSopsSecrets.test-secret.key == "test-secret" &&
                  testMkSopsSecrets.test-secret.owner == "testuser" &&
                  testMkSopsSecrets.test-secret.mode == "0440";
    
    secretAccessors = testSecretAccessors ? test-secret &&
                      testSecretAccessors.test-secret == "/run/secrets/test-secret" &&
                      testSecretAccessors ? complex-secret &&
                      testSecretAccessors ? note-secret;
    
    syncScript = testSyncScript != null;
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-lib-function-tests";
  
  buildCommand = ''
    echo "🧪 Starting sopswarden library function tests..."
    
    # Test results
    if [ "${toString assertions.simple}" = "1" ]; then
      simple_result="PASS"
    else
      simple_result="FAIL"
    fi
    if [ "${toString assertions.complex}" = "1" ]; then
      complex_result="PASS"
    else
      complex_result="FAIL"
    fi
    if [ "${toString assertions.note}" = "1" ]; then
      note_result="PASS"
    else
      note_result="FAIL"
    fi
    if [ "${toString assertions.complete}" = "1" ]; then
      complete_result="PASS"
    else
      complete_result="FAIL"
    fi
    if [ "${toString assertions.sopsSecrets}" = "1" ]; then
      sops_result="PASS"
    else
      sops_result="FAIL"
    fi
    if [ "${toString assertions.secretAccessors}" = "1" ]; then
      accessors_result="PASS"
    else
      accessors_result="FAIL"
    fi
    if [ "${toString assertions.syncScript}" = "1" ]; then
      script_result="PASS"
    else
      script_result="FAIL"
    fi
    
    echo "📋 Testing normalizeSecretDef..."
    echo "  Simple string test: $simple_result"
    echo "  Complex object test: $complex_result"
    echo "  Note object test: $note_result"
    echo "  Complete object test: $complete_result"
    
    echo "📋 Testing mkSopsSecrets..."
    echo "  SOPS secrets generation: $sops_result"
    
    echo "📋 Testing mkSecretAccessors..."
    echo "  Secret accessors generation: $accessors_result"
    
    echo "📋 Testing mkSyncScript..."
    echo "  Sync script generation: $script_result"
    
    # Detailed test output for debugging
    echo ""
    echo "🔍 Detailed test results:"
    
    if [ "$simple_result" = "FAIL" ]; then
      echo "❌ Simple test failed:"
      echo "  Expected: ${builtins.toJSON testNormalizeSecretDef.expected_simple}"
      echo "  Got: ${builtins.toJSON testNormalizeSecretDef.simple}"
    fi
    
    if [ "$sops_result" = "FAIL" ]; then
      echo "❌ SOPS secrets test failed:"
      echo "  Generated: ${builtins.toJSON testMkSopsSecrets}"
    fi
    
    if [ "$accessors_result" = "FAIL" ]; then
      echo "❌ Secret accessors test failed:"
      echo "  Generated: ${builtins.toJSON testSecretAccessors}"
    fi
    
    # Check if all tests passed
    if [ "$simple_result" = "PASS" ] && \
       [ "$complex_result" = "PASS" ] && \
       [ "$note_result" = "PASS" ] && \
       [ "$complete_result" = "PASS" ] && \
       [ "$sops_result" = "PASS" ] && \
       [ "$accessors_result" = "PASS" ] && \
       [ "$script_result" = "PASS" ]; then
      echo "🎉 All library function tests passed!"
      mkdir -p $out
      echo "success" > $out/result
    else
      echo "❌ Some tests failed!"
      exit 1
    fi
  '';
}