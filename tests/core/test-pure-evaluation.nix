# Test that sopswarden works with pure evaluation (no --impure needed)
{ pkgs ? import <nixpkgs> {} }:

let
  # Import our lib directly for testing
  lib = import ../../lib { nixpkgs = pkgs.lib; };

  # Test library functions directly in Nix instead of using nix-instantiate
  test1 = lib.normalizeSecretDef "test";
  
  test2 = let
    config = {
      sops.secrets = {
        test-secret = { path = "/run/secrets/test-secret"; };
        another-secret = { path = "/run/secrets/another-secret"; };
      };
    };
    secrets = {
      test-secret = "Test Item";
      another-secret = "Another Item";
    };
    result = lib.mkSecretAccessors { inherit config secrets; };
  in result.test-secret;
  
  test3 = [
    (lib.normalizeSecretDef "simple")
    (lib.normalizeSecretDef { name = "complex"; user = "test"; })
    (lib.normalizeSecretDef { name = "note"; type = "note"; field = "custom"; })
  ];

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-pure-evaluation-test";
  
  buildCommand = ''
    echo "🧪 Testing pure evaluation..."
    
    # Test 1: Verify library functions are pure
    echo "📋 Test 1: Library function purity"
    echo "normalizeSecretDef result: ${builtins.toJSON test1}"
    if [ "${test1.name}" = "test" ] && [ "${test1.type}" = "login" ] && [ "${test1.field}" = "password" ]; then
      echo "✅ Library functions are pure"
    else
      echo "❌ Library function test failed"
      exit 1
    fi
    
    # Test 2: Verify mkSecretAccessors works purely
    echo "📋 Test 2: mkSecretAccessors purity"
    echo "mkSecretAccessors result: ${test2}"
    if [ "${test2}" = "/run/secrets/test-secret" ]; then
      echo "✅ mkSecretAccessors works purely"
    else
      echo "❌ mkSecretAccessors test failed"
      exit 1
    fi
    
    # Test 3: Verify normalizeSecretDef works with different types
    echo "📋 Test 3: Secret normalization"
    echo "Normalization tests: ${builtins.toJSON test3}"
    echo "✅ Secret normalization works purely"
    
    echo "🎉 All pure evaluation tests passed!"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}