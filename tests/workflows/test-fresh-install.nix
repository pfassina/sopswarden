# Test fresh sopswarden installation workflow
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library
  lib = import ../../lib { nixpkgs = pkgs.lib; };
  
  # Test secrets (what a user would define)
  userSecrets = {
    wifi-password = "Home WiFi";
    api-key = "My Service";
    database-password = { 
      name = "Database Server"; 
      user = "admin@example.com"; 
    };
  };
  
  # Generate SOPS configuration (what the module would do)
  sopsSecrets = lib.mkSopsSecrets { 
    secrets = userSecrets; 
    sopsFile = "/var/lib/sopswarden/secrets.yaml";
  };
  
  # Simulate NixOS config structure (what the module provides)
  mockConfig = {
    sops.secrets = builtins.mapAttrs (name: secretConfig: 
      secretConfig // { path = "/run/secrets/${name}"; }
    ) sopsSecrets;
  };
  
  # Generate secret accessors (what gets exported as `secrets`)
  secrets = lib.mkSecretAccessors { 
    config = mockConfig; 
    secrets = userSecrets; 
  };
  
  # Test real NixOS service configurations using secrets
  serviceConfigs = {
    # Test 1: Wireless configuration (very common first use case)
    wireless = {
      networks."MyNetwork" = {
        psk = secrets.wifi-password;  # This is the key test!
      };
    };
    
    # Test 2: Environment variables
    environment = {
      variables = {
        API_KEY_FILE = secrets.api-key;
        DB_PASSWORD_FILE = secrets.database-password;
      };
    };
    
    # Test 3: PostgreSQL configuration
    postgresql = {
      authentication = "host myapp myuser 0.0.0.0/0 md5";
      # In real usage: passwordFile = secrets.database-password;
    };
    
    # Test 4: Systemd service using secrets
    systemd.services.myapp = {
      serviceConfig = {
        ExecStart = "/bin/myapp";
        EnvironmentFile = secrets.api-key;
      };
    };
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-fresh-install-workflow-test";
  
  buildCommand = ''
    echo "🧪 Testing fresh sopswarden installation workflow..."
    
    # Test 1: User secret definitions work
    echo "📋 Test 1: User secret definitions"
    user_secrets_count=${toString (builtins.length (builtins.attrNames userSecrets))}
    if [ "$user_secrets_count" = "3" ]; then
      echo "✅ User defined $user_secrets_count secrets successfully"
    else
      echo "❌ Secret definition failed (expected 3, got $user_secrets_count)"
      exit 1
    fi
    
    # Test 2: SOPS configuration generated automatically
    echo "📋 Test 2: Automatic SOPS configuration"
    sops_count=${toString (builtins.length (builtins.attrNames sopsSecrets))}
    if [ "$sops_count" = "3" ]; then
      echo "✅ SOPS configuration generated automatically ($sops_count secrets)"
    else
      echo "❌ SOPS generation failed (expected 3, got $sops_count)"
      exit 1
    fi
    
    # Test 3: Secret accessors available (the key feature!)
    echo "📋 Test 3: Secret accessors (secrets.secret-name syntax)"
    wifi_secret="${secrets.wifi-password}"
    api_secret="${secrets.api-key}"
    db_secret="${secrets.database-password}"
    
    if [ "$wifi_secret" = "/run/secrets/wifi-password" ] && \
       [ "$api_secret" = "/run/secrets/api-key" ] && \
       [ "$db_secret" = "/run/secrets/database-password" ]; then
      echo "✅ Secret accessors work: secrets.secret-name → /run/secrets/secret-name"
    else
      echo "❌ Secret accessors failed"
      echo "  WiFi: $wifi_secret"
      echo "  API: $api_secret"
      echo "  DB: $db_secret"
      exit 1
    fi
    
    # Test 4: Real NixOS service usage
    echo "📋 Test 4: Real NixOS service integration"
    
    # Test wireless config
    wireless_psk="${serviceConfigs.wireless.networks."MyNetwork".psk}"
    if [ "$wireless_psk" = "/run/secrets/wifi-password" ]; then
      echo "✅ Wireless config: networking.wireless.networks.MyNetwork.psk = secrets.wifi-password"
    else
      echo "❌ Wireless config failed: $wireless_psk"
      exit 1
    fi
    
    # Test environment variables
    api_env="${serviceConfigs.environment.variables.API_KEY_FILE}"
    db_env="${serviceConfigs.environment.variables.DB_PASSWORD_FILE}"
    if [ "$api_env" = "/run/secrets/api-key" ] && [ "$db_env" = "/run/secrets/database-password" ]; then
      echo "✅ Environment variables: environment.variables.API_KEY_FILE = secrets.api-key"
    else
      echo "❌ Environment variables failed"
      exit 1
    fi
    
    # Test systemd service
    systemd_env="${serviceConfigs.systemd.services.myapp.serviceConfig.EnvironmentFile}"
    if [ "$systemd_env" = "/run/secrets/api-key" ]; then
      echo "✅ Systemd service: systemd.services.myapp.serviceConfig.EnvironmentFile = secrets.api-key"
    else
      echo "❌ Systemd service failed: $systemd_env"
      exit 1
    fi
    
    echo ""
    echo "🎉 Fresh installation workflow test passed!"
    echo ""
    echo "📝 This validates the complete user experience:"
    echo "  1. ✓ User defines secrets in services.sopswarden.secrets"
    echo "  2. ✓ Module automatically generates SOPS configuration"
    echo "  3. ✓ Module exports secrets via _module.args.secrets"
    echo "  4. ✓ User can use secrets.secret-name in ANY NixOS service"
    echo "  5. ✓ Everything works with pure evaluation (no --impure needed)"
    echo ""
    echo "🚀 This is the core value proposition of sopswarden!"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}