# Integration test for sopswarden sync functionality
{ pkgs ? import <nixpkgs> {} }:

let
  # Mock rbw command that returns test data
  mockRbw = pkgs.writeShellScriptBin "mock-rbw" ''
    #!/usr/bin/env bash
    case "$1" in
      "ls")
        echo "test-item"
        echo "wifi-config"
        echo "database-server"
        ;;
      "get")
        case "$2" in
          "test-item")
            echo "secret-password-123"
            ;;
          "wifi-config")
            if [[ "$3" == "--field" && "$4" == "password" ]]; then
              echo "wifi-secret-456"
            fi
            ;;
          "database-server")
            if [[ "$3" == "admin@test.com" ]]; then
              echo "db-password-789"
            fi
            ;;
          *)
            echo "Unknown item: $2" >&2
            exit 1
            ;;
        esac
        ;;
      *)
        echo "Unknown command: $1" >&2
        exit 1
        ;;
    esac
  '';

  # Test secrets definition
  testSecretsNix = pkgs.writeText "test-secrets.nix" ''
    {
      secrets = {
        simple-secret = "test-item";
        wifi-password = {
          name = "wifi-config";
          type = "note";
          field = "password";
        };
        database-password = {
          name = "database-server";
          user = "admin@test.com";
        };
      };
    }
  '';

  # Test SOPS configuration
  testSopsYaml = pkgs.writeText ".sops.yaml" ''
    keys:
      - &test_key age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
    creation_rules:
      - path_regex: test-secrets\.ya?ml$
        key_groups:
        - age:
          - *test_key
  '';

  # Import sopswarden library
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };

  # Create sync script with mock rbw
  syncScript = sopswardenLib.mkSyncScript {
    inherit pkgs;
    secretsFile = toString testSecretsNix;
    sopsFile = "./test-secrets.yaml";
    sopsConfigFile = toString testSopsYaml;
    rbwCommand = "${mockRbw}/bin/mock-rbw";
    workingDirectory = "/tmp/sopswarden-test";
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-integration-test";
  
  buildInputs = with pkgs; [
    syncScript
    sops
    age
    jq
    bash
  ];

  buildCommand = ''
    set -euo pipefail
    
    echo "🧪 Starting sopswarden integration tests..."
    
    # Create test directory
    mkdir -p /tmp/sopswarden-test
    cd /tmp/sopswarden-test
    
    # Copy test files
    cp ${testSecretsNix} secrets.nix
    cp ${testSopsYaml} .sops.yaml
    
    # Generate test age key
    mkdir -p ~/.config/sops/age
    echo "AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ" > ~/.config/sops/age/keys.txt
    
    # Test 1: Check if sync script is available
    echo "📋 Test 1: Sync script availability"
    if command -v sopswarden-sync &> /dev/null; then
      echo "✅ sopswarden-sync command found"
    else
      echo "❌ sopswarden-sync command not found"
      exit 1
    fi
    
    # Test 2: Run sync script with mock rbw
    echo "📋 Test 2: Sync script execution"
    if sopswarden-sync; then
      echo "✅ Sync script executed successfully"
    else
      echo "❌ Sync script failed"
      exit 1
    fi
    
    # Test 3: Check if secrets.yaml was created
    echo "📋 Test 3: Encrypted secrets file creation"
    if [[ -f "test-secrets.yaml" ]]; then
      echo "✅ Encrypted secrets file created"
    else
      echo "❌ Encrypted secrets file not found"
      exit 1
    fi
    
    # Test 4: Verify encrypted content can be decrypted
    echo "📋 Test 4: Decrypt and verify content"
    if sops -d test-secrets.yaml | grep -q "simple-secret"; then
      echo "✅ Encrypted content can be decrypted"
    else
      echo "❌ Failed to decrypt or find expected content"
      exit 1
    fi
    
    # Test 5: Verify hash tracking
    echo "📋 Test 5: Hash tracking functionality"
    if [[ -f ".last-sync-hash" ]]; then
      echo "✅ Hash tracking file created"
      
      # Run sync again, should skip
      if sopswarden-sync | grep -q "unchanged since last sync"; then
        echo "✅ Change detection working correctly"
      else
        echo "❌ Change detection not working"
        exit 1
      fi
    else
      echo "❌ Hash tracking file not found"
      exit 1
    fi
    
    echo "🎉 All integration tests passed!"
    
    # Create success marker
    mkdir -p $out
    echo "success" > $out/result
  '';
}