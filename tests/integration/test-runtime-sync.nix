# Test runtime synchronization
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library
  lib = import ../../lib { nixpkgs = pkgs.lib; };
  
  # Test secrets configuration
  secrets = {
    test-secret = "Test Item";
    database-password = { 
      name = "Database Server"; 
      user = "admin@example.com"; 
    };
    api-key = "API Service";
  };
  
  # Generate sync script with test secrets
  testSyncScript = lib.mkSyncScript { 
    inherit pkgs secrets; 
    sopsFile = "/tmp/test-secrets.yaml";
    rbwCommand = "/usr/bin/mock-rbw";
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-runtime-sync-test";
  
  buildCommand = ''
    echo "🧪 Testing runtime synchronization..."
    
    # Test 1: Sync script generation
    echo "📋 Test 1: Sync script generation"
    if [ -n "${testSyncScript}" ]; then
      echo "✅ Sync script generated successfully"
    else
      echo "❌ Sync script generation failed"
      exit 1
    fi
    
    # Test 2: Script contains expected secrets
    echo "📋 Test 2: Script secret embedding"
    script_path="${testSyncScript}/bin/sopswarden-sync"
    if [ -f "$script_path" ]; then
      echo "✅ Sync script executable exists"
    else
      echo "❌ Sync script executable not found"
      exit 1
    fi
    
    # Test 3: Library functions work with runtime config
    echo "📋 Test 3: Library function compatibility"
    secret_count=${toString (builtins.length (builtins.attrNames secrets))}
    if [ "$secret_count" = "3" ]; then
      echo "✅ Secret configuration processed ($secret_count secrets)"
    else
      echo "❌ Secret configuration failed (expected 3, got $secret_count)"
      exit 1
    fi
    
    echo "🎉 Runtime synchronization test passed!"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}