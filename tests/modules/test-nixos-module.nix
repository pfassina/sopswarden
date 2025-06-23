# Test NixOS module functionality
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library
  lib = import ../../lib { nixpkgs = pkgs.lib; };
  
  # Test secrets configuration
  testSecrets = {
    simple-secret = "Test Item";
    complex-secret = {
      name = "Complex Item";
      user = "test@example.com";
    };
    note-secret = {
      name = "Note Item";
      type = "note";
      field = "custom_field";
    };
  };
  
  # Simulate SOPS configuration generation (what the module would do)
  sopsSecrets = lib.mkSopsSecrets { 
    secrets = testSecrets; 
    sopsFile = "/var/lib/sopswarden/secrets.yaml";
  };
  
  # Simulate config structure (what NixOS would provide)
  mockConfig = {
    sops.secrets = builtins.mapAttrs (name: secretConfig: 
      secretConfig // { path = "/run/secrets/${name}"; }
    ) sopsSecrets;
  };
  
  # Test secret accessor generation (core module functionality)
  secretAccessors = lib.mkSecretAccessors { 
    config = mockConfig; 
    secrets = testSecrets; 
  };
  
  # Simulate how secrets would be used in NixOS services
  serviceConfigurations = {
    # Test wireless config (common use case)
    wireless = {
      networks."MyNetwork".psk = secretAccessors.simple-secret;
    };
    
    # Test PostgreSQL config
    postgresql = {
      authentication = "host myapp myuser 0.0.0.0/0 md5";
      # Would use secretAccessors.complex-secret for password
    };
    
    # Test environment variables
    environment = {
      variables.API_KEY_FILE = secretAccessors.note-secret;
    };
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-nixos-module-test";
  
  buildCommand = ''
    echo "🧪 Testing NixOS module core functionality..."
    
    # Test 1: SOPS secrets generation
    echo "📋 Test 1: SOPS secrets generation"
    sops_count=${toString (builtins.length (builtins.attrNames sopsSecrets))}
    if [ "$sops_count" = "3" ]; then
      echo "✅ SOPS secrets generated ($sops_count secrets)"
    else
      echo "❌ SOPS generation failed (expected 3, got $sops_count)"
      exit 1
    fi
    
    # Test 2: Secret accessor paths
    echo "📋 Test 2: Secret accessor paths"
    simple_path="${secretAccessors.simple-secret}"
    complex_path="${secretAccessors.complex-secret}"
    note_path="${secretAccessors.note-secret}"
    
    if [ "$simple_path" = "/run/secrets/simple-secret" ] && \
       [ "$complex_path" = "/run/secrets/complex-secret" ] && \
       [ "$note_path" = "/run/secrets/note-secret" ]; then
      echo "✅ Secret accessors generate correct paths"
    else
      echo "❌ Secret accessor paths incorrect"
      echo "  Simple: $simple_path (expected /run/secrets/simple-secret)"
      echo "  Complex: $complex_path (expected /run/secrets/complex-secret)"
      echo "  Note: $note_path (expected /run/secrets/note-secret)"
      exit 1
    fi
    
    # Test 3: Service integration simulation
    echo "📋 Test 3: Service integration simulation"
    wireless_psk="${serviceConfigurations.wireless.networks."MyNetwork".psk}"
    api_var="${serviceConfigurations.environment.variables.API_KEY_FILE}"
    
    if [ "$wireless_psk" = "/run/secrets/simple-secret" ] && \
       [ "$api_var" = "/run/secrets/note-secret" ]; then
      echo "✅ Services can access secrets via accessors"
    else
      echo "❌ Service integration failed"
      echo "  Wireless PSK: $wireless_psk"
      echo "  API var: $api_var"
      exit 1
    fi
    
    # Test 4: SOPS file configuration
    echo "📋 Test 4: SOPS file configuration"
    simple_sops_file="${sopsSecrets.simple-secret.sopsFile}"
    if [ "$simple_sops_file" = "/var/lib/sopswarden/secrets.yaml" ]; then
      echo "✅ SOPS file path configured correctly"
    else
      echo "❌ SOPS file path incorrect: $simple_sops_file"
      exit 1
    fi
    
    echo "🎉 NixOS module core functionality test passed!"
    echo ""
    echo "📝 This validates:"
    echo "  ✓ Secret definitions → SOPS configuration"
    echo "  ✓ Secret accessors → Runtime paths"
    echo "  ✓ Service integration via secrets.secret-name"
    echo "  ✓ Pure evaluation (no file access required)"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}