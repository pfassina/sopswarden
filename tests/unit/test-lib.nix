# Unit tests for sopswarden library functions
{ pkgs ? import <nixpkgs> {} }:

let
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };
  
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
  };

  # Test mkSopsSecrets function
  testMkSopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = { test-secret = "Test Item"; };
  };

  # Run assertions
  simpleTest = testNormalizeSecretDef.simple == testNormalizeSecretDef.expected_simple;
  complexTest = testNormalizeSecretDef.complex == testNormalizeSecretDef.expected_complex;
  noteTest = testNormalizeSecretDef.note == testNormalizeSecretDef.expected_note;
  sopsTest = testMkSopsSecrets ? test-secret && testMkSopsSecrets.test-secret.key == "test-secret";

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-unit-tests";
  
  buildCommand = ''
    echo "🧪 Starting sopswarden unit tests..."
    
    # Test results
    simple_result="${if simpleTest then "PASS" else "FAIL"}"
    complex_result="${if complexTest then "PASS" else "FAIL"}"
    note_result="${if noteTest then "PASS" else "FAIL"}"
    sops_result="${if sopsTest then "PASS" else "FAIL"}"
    
    echo "📋 Testing normalizeSecretDef..."
    echo "✅ Simple string test: $simple_result"
    echo "✅ Complex object test: $complex_result"
    echo "✅ Note object test: $note_result"
    
    echo "📋 Testing mkSopsSecrets..."
    echo "✅ SOPS secrets generation: $sops_result"
    
    # Check if all tests passed
    if [ "$simple_result" = "PASS" ] && \
       [ "$complex_result" = "PASS" ] && \
       [ "$note_result" = "PASS" ] && \
       [ "$sops_result" = "PASS" ]; then
      echo "🎉 All unit tests passed!"
      mkdir -p $out
      echo "success" > $out/result
    else
      echo "❌ Some tests failed!"
      exit 1
    fi
  '';
}