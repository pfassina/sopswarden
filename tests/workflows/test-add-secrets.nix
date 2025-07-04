# Test adding new secrets after initial installation
# Simulates a user who already has sopswarden configured and wants to add more secrets

let
  flake = builtins.getFlake (toString ../..);

  # Initial configuration (existing state)
  initialConfig = { ... }: {
    imports = [ flake.nixosModules.default ];

    # Required for NixOS system evaluation
    system.stateVersion = "25.11";

    services.sopswarden = {
      enable = true;
      secrets = {
        # Existing secrets
        wifi-password = "Home WiFi";
        api-key = {
          name = "My Service API";
          user = "admin@example.com";
        };
      };
    };
  };

  # Updated configuration (after adding new secrets)
  updatedConfig = { ... }: {
    imports = [ flake.nixosModules.default ];

    # Required for NixOS system evaluation
    system.stateVersion = "25.11";

    services.sopswarden = {
      enable = true;
      secrets = {
        # Existing secrets (unchanged)
        wifi-password = "Home WiFi";
        api-key = {
          name = "My Service API";
          user = "admin@example.com";
        };

        # New secrets added
        database-password = {
          name = "Production Database";
          user = "db-admin@company.com";
          type = "login";
          field = "password";
        };

        ssl-cert = {
          name = "SSL Certificate";
          type = "note";
          field = "notes";
        };

        backup-key = "Backup Encryption Key";
      };
    };
  };

  # Evaluate both configurations using nixosSystem for full module environment
  initialSystem = flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ initialConfig ];
  };

  updatedSystem = flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ updatedConfig ];
  };

  # Test results
  testResults = {
    # Initial state
    initialSecretCount = builtins.length (builtins.attrNames initialSystem.config.services.sopswarden.secrets);
    initialHasWifi = builtins.hasAttr "wifi-password" initialSystem.config.services.sopswarden.secrets;
    initialHasApi = builtins.hasAttr "api-key" initialSystem.config.services.sopswarden.secrets;

    # Updated state
    updatedSecretCount = builtins.length (builtins.attrNames updatedSystem.config.services.sopswarden.secrets);
    updatedHasWifi = builtins.hasAttr "wifi-password" updatedSystem.config.services.sopswarden.secrets;
    updatedHasApi = builtins.hasAttr "api-key" updatedSystem.config.services.sopswarden.secrets;

    # New secrets
    hasDatabase = builtins.hasAttr "database-password" updatedSystem.config.services.sopswarden.secrets;
    hasSslCert = builtins.hasAttr "ssl-cert" updatedSystem.config.services.sopswarden.secrets;
    hasBackupKey = builtins.hasAttr "backup-key" updatedSystem.config.services.sopswarden.secrets;

    # Verify secret types are preserved
    databaseSecret = updatedSystem.config.services.sopswarden.secrets.database-password;
    sslSecret = updatedSystem.config.services.sopswarden.secrets.ssl-cert;
    backupSecret = updatedSystem.config.services.sopswarden.secrets.backup-key;

    # Check that existing secrets are unchanged
    wifiUnchanged = initialSystem.config.services.sopswarden.secrets.wifi-password ==
      updatedSystem.config.services.sopswarden.secrets.wifi-password;
    apiUnchanged = initialSystem.config.services.sopswarden.secrets.api-key ==
      updatedSystem.config.services.sopswarden.secrets.api-key;
  };

in
{
  # Test adding secrets workflow
  addSecrets = testResults;

  # Validate the workflow works correctly
  success =
    testResults.initialSecretCount == 2 &&
    testResults.updatedSecretCount == 5 &&
    testResults.updatedHasWifi &&
    testResults.updatedHasApi &&
    testResults.hasDatabase &&
    testResults.hasSslCert &&
    testResults.hasBackupKey &&
    testResults.wifiUnchanged &&
    testResults.apiUnchanged;

  # Detailed validation
  validation = {
    correctInitialState = testResults.initialSecretCount == 2;
    correctUpdatedState = testResults.updatedSecretCount == 5;
    existingSecretsPreserved = testResults.wifiUnchanged && testResults.apiUnchanged;
    newSecretsAdded = testResults.hasDatabase && testResults.hasSslCert && testResults.hasBackupKey;
    secretCountIncreased = testResults.updatedSecretCount > testResults.initialSecretCount;
  };
}
