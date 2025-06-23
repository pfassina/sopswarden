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
    if [ "${toString simpleTest}" = "true" ]; then
      simple_result="PASS"
    else
      simple_result="FAIL"
    fi
    
    if [ "${toString complexTest}" = "true" ]; then
      complex_result="PASS"
    else
      complex_result="FAIL"
    fi
    
    if [ "${toString noteTest}" = "true" ]; then
      note_result="PASS"
    else
      note_result="FAIL"
    fi
    
    if [ "${toString sopsTest}" = "true" ]; then
      sops_result="PASS"
    else
      sops_result="FAIL"
    fi
    
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