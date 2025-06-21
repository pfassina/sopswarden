# Unit tests for sopswarden library functions
{ pkgs ? import <nixpkgs> {} }:

let
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };
  
  # Test data
  testSecrets = {
    simple-secret = "Test Item";
    complex-secret = {
      name = "Complex Item";
      user = "test@example.com";
      type = "login";
      field = "password";
    };
    note-secret = {
      name = "Note Item";
      type = "note";
      field = "custom_field";
    };
  };

  # Helper function to run assertions
  assert = condition: message:
    if condition
    then pkgs.lib.trace "✅ ${message}" true
    else pkgs.lib.trace "❌ ${message}" (throw "Test failed: ${message}");

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-unit-tests";
  
  buildCommand = ''
    set -euo pipefail
    
    echo "🧪 Starting sopswarden unit tests..."
    
    # Test normalizeSecretDef function
    echo "📋 Testing normalizeSecretDef..."
    
    ${pkgs.nix}/bin/nix eval --impure --expr '
      let
        lib = import ${../../lib} { nixpkgs = import <nixpkgs> {}; };
        
        # Test simple string input
        simple = lib.normalizeSecretDef "Test Item";
        expected_simple = {
          name = "Test Item";
          user = null;
          type = "login";
          field = "password";
        };
        
        # Test complex input
        complex = lib.normalizeSecretDef {
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
        note = lib.normalizeSecretDef {
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
        
      in {
        simple_test = simple == expected_simple;
        complex_test = complex == expected_complex;
        note_test = note == expected_note;
      }
    ' > test_results.json
    
    # Check test results
    if ${pkgs.jq}/bin/jq -e '.simple_test' test_results.json > /dev/null; then
      echo "✅ normalizeSecretDef simple test passed"
    else
      echo "❌ normalizeSecretDef simple test failed"
      exit 1
    fi
    
    if ${pkgs.jq}/bin/jq -e '.complex_test' test_results.json > /dev/null; then
      echo "✅ normalizeSecretDef complex test passed"
    else
      echo "❌ normalizeSecretDef complex test failed"
      exit 1
    fi
    
    if ${pkgs.jq}/bin/jq -e '.note_test' test_results.json > /dev/null; then
      echo "✅ normalizeSecretDef note test passed"
    else
      echo "❌ normalizeSecretDef note test failed"
      exit 1
    fi
    
    # Test mkSopsSecrets function
    echo "📋 Testing mkSopsSecrets..."
    
    ${pkgs.nix}/bin/nix eval --impure --expr '
      let
        lib = import ${../../lib} { nixpkgs = import <nixpkgs> {}; };
        secrets = { test-secret = "Test Item"; };
        result = lib.mkSopsSecrets { inherit secrets; };
      in {
        has_test_secret = builtins.hasAttr "test-secret" result;
        correct_structure = result.test-secret.key == "test-secret" &&
                           result.test-secret.owner == "root" &&
                           result.test-secret.group == "root" &&
                           result.test-secret.mode == "0400";
      }
    ' > sops_test_results.json
    
    if ${pkgs.jq}/bin/jq -e '.has_test_secret and .correct_structure' sops_test_results.json > /dev/null; then
      echo "✅ mkSopsSecrets test passed"
    else
      echo "❌ mkSopsSecrets test failed"
      exit 1
    fi
    
    echo "🎉 All unit tests passed!"
    
    # Create success marker
    mkdir -p $out
    echo "success" > $out/result
  '';
}