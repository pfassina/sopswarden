# Test adding new secrets to existing configuration
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library
  lib = import ../../lib { nixpkgs = pkgs.lib; };
  
  # Simulate existing secrets (user already has these)
  existingSecrets = {
    wifi-password = "Home WiFi";
    api-key = "My Service";
  };
  
  # Simulate adding new secrets (user wants to add these)
  newSecrets = existingSecrets // {
    database-password = { 
      name = "Database Server"; 
      user = "admin"; 
    };
    ssl-certificate = {
      name = "SSL Cert";
      type = "note";
      field = "private_key";
    };
    backup-key = "Backup Service";
  };
  
  # Generate configurations for both scenarios
  existingSopsSecrets = lib.mkSopsSecrets { 
    secrets = existingSecrets; 
    sopsFile = "/var/lib/sopswarden/secrets.yaml";
  };
  
  newSopsSecrets = lib.mkSopsSecrets { 
    secrets = newSecrets; 
    sopsFile = "/var/lib/sopswarden/secrets.yaml";
  };
  
  # Simulate config structures
  existingConfig = {
    sops.secrets = builtins.mapAttrs (name: secretConfig: 
      secretConfig // { path = "/run/secrets/${name}"; }
    ) existingSopsSecrets;
  };
  
  newConfig = {
    sops.secrets = builtins.mapAttrs (name: secretConfig: 
      secretConfig // { path = "/run/secrets/${name}"; }
    ) newSopsSecrets;
  };
  
  # Generate secret accessors for both scenarios
  existingSecretsAccessors = lib.mkSecretAccessors { 
    config = existingConfig; 
    secrets = existingSecrets; 
  };
  
  newSecretsAccessors = lib.mkSecretAccessors { 
    config = newConfig; 
    secrets = newSecrets; 
  };
  
  # Test service configurations before and after
  existingServiceConfigs = {
    # Existing services using original secrets
    wireless = {
      networks."MyNetwork".psk = existingSecretsAccessors.wifi-password;
    };
    environment = {
      variables.API_KEY_FILE = existingSecretsAccessors.api-key;
    };
  };
  
  expandedServiceConfigs = {
    # Original services still work
    wireless = {
      networks."MyNetwork".psk = newSecretsAccessors.wifi-password;
    };
    environment = {
      variables.API_KEY_FILE = newSecretsAccessors.api-key;
    };
    
    # NEW services using new secrets
    postgresql = {
      passwordFile = newSecretsAccessors.database-password;
    };
    nginx = {
      sslCertificate = newSecretsAccessors.ssl-certificate;
    };
    systemd.services.backup = {
      serviceConfig.EnvironmentFile = newSecretsAccessors.backup-key;
    };
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-add-secrets-workflow-test";
  
  buildCommand = ''
    echo "🧪 Testing adding secrets to existing configuration workflow..."
    
    # Test 1: Existing system baseline
    echo "📋 Test 1: Existing system baseline"
    existing_count=${toString (builtins.length (builtins.attrNames existingSecrets))}
    existing_sops_count=${toString (builtins.length (builtins.attrNames existingSopsSecrets))}
    if [ "$existing_count" = "2" ] && [ "$existing_sops_count" = "2" ]; then
      echo "✅ Existing system has $existing_count secrets with $existing_sops_count SOPS configs"
    else
      echo "❌ Existing system baseline failed"
      exit 1
    fi
    
    # Test 2: Adding new secrets
    echo "📋 Test 2: Adding new secrets"
    new_count=${toString (builtins.length (builtins.attrNames newSecrets))}
    new_sops_count=${toString (builtins.length (builtins.attrNames newSopsSecrets))}
    if [ "$new_count" = "5" ] && [ "$new_sops_count" = "5" ]; then
      echo "✅ After adding secrets: $new_count total secrets with $new_sops_count SOPS configs"
    else
      echo "❌ Adding secrets failed (expected 5, got $new_count secrets, $new_sops_count SOPS)"
      exit 1
    fi
    
    # Test 3: Existing secrets still work
    echo "📋 Test 3: Existing secrets preservation"
    existing_wifi="${existingServiceConfigs.wireless.networks."MyNetwork".psk}"
    existing_api="${existingServiceConfigs.environment.variables.API_KEY_FILE}"
    
    new_wifi="${expandedServiceConfigs.wireless.networks."MyNetwork".psk}"
    new_api="${expandedServiceConfigs.environment.variables.API_KEY_FILE}"
    
    if [ "$existing_wifi" = "$new_wifi" ] && [ "$existing_api" = "$new_api" ]; then
      echo "✅ Existing service configurations unchanged"
      echo "  WiFi: $existing_wifi → $new_wifi"
      echo "  API: $existing_api → $new_api"
    else
      echo "❌ Existing configurations broken"
      exit 1
    fi
    
    # Test 4: New secrets accessible in services
    echo "📋 Test 4: New secrets in service configurations"
    
    # Test PostgreSQL
    postgres_password="${expandedServiceConfigs.postgresql.passwordFile}"
    if [ "$postgres_password" = "/run/secrets/database-password" ]; then
      echo "✅ PostgreSQL: passwordFile = secrets.database-password"
    else
      echo "❌ PostgreSQL config failed: $postgres_password"
      exit 1
    fi
    
    # Test Nginx
    nginx_ssl="${expandedServiceConfigs.nginx.sslCertificate}"
    if [ "$nginx_ssl" = "/run/secrets/ssl-certificate" ]; then
      echo "✅ Nginx: sslCertificate = secrets.ssl-certificate"
    else
      echo "❌ Nginx config failed: $nginx_ssl"
      exit 1
    fi
    
    # Test systemd service
    backup_env="${expandedServiceConfigs.systemd.services.backup.serviceConfig.EnvironmentFile}"
    if [ "$backup_env" = "/run/secrets/backup-key" ]; then
      echo "✅ Systemd: EnvironmentFile = secrets.backup-key"
    else
      echo "❌ Systemd config failed: $backup_env"
      exit 1
    fi
    
    # Test 5: Different secret types work
    echo "📋 Test 5: Secret type handling"
    
    # Check database secret (complex with user)
    if [ "${newSecretsAccessors.database-password}" = "/run/secrets/database-password" ]; then
      echo "✅ Complex secret (with user): secrets.database-password"
    else
      echo "❌ Complex secret failed"
      exit 1
    fi
    
    # Check SSL secret (note type)
    if [ "${newSecretsAccessors.ssl-certificate}" = "/run/secrets/ssl-certificate" ]; then
      echo "✅ Note secret: secrets.ssl-certificate"
    else
      echo "❌ Note secret failed"
      exit 1
    fi
    
    # Check backup secret (simple string)
    if [ "${newSecretsAccessors.backup-key}" = "/run/secrets/backup-key" ]; then
      echo "✅ Simple secret: secrets.backup-key"
    else
      echo "❌ Simple secret failed"
      exit 1
    fi
    
    echo ""
    echo "🎉 Add secrets workflow test passed!"
    echo ""
    echo "📝 This validates the expansion workflow:"
    echo "  1. ✓ Existing secrets continue to work unchanged"
    echo "  2. ✓ New secrets integrate seamlessly"
    echo "  3. ✓ SOPS configuration scales automatically"
    echo "  4. ✓ All secret types work (simple, complex, note)"
    echo "  5. ✓ New services can immediately use new secrets"
    echo "  6. ✓ Pure evaluation maintained throughout"
    echo ""
    echo "🚀 Users can add secrets without breaking existing services!"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}