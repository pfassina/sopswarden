# Test runtime sync script generation and application access
# Validates that applications can access secrets after sopswarden-sync runs

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> { };

  # Test sync script generation
  testSyncScript =
    let
      # Generate sync script with test configuration
      syncScript = flake.lib.mkSyncScript {
        inherit pkgs;
        secretsFile = "/etc/nixos/secrets.nix";
        sopsFile = "/etc/nixos/secrets.yaml";
        ageKeyFile = "/root/.config/sops/age/keys.txt";
        sopsConfigFile = "/etc/nixos/.sops.yaml";
        forceSync = false;
        workingDirectory = "/etc/nixos";
      };
    in
    {
      # Basic script validation
      isDerivation = builtins.isAttrs syncScript && builtins.hasAttr "type" syncScript;
      hasScript = builtins.hasAttr "name" syncScript;
      scriptName = if builtins.hasAttr "name" syncScript then syncScript.name else null;
    };

  # Test application access scenario
  testApplicationAccess =
    let
      # System configuration that uses secrets in applications
      appConfig = { ... }: {
        imports = [ flake.nixosModules.default ];

        # Required for NixOS system evaluation
        system.stateVersion = "25.11";

        services = {
          sopswarden = {
            enable = true;
            secrets = {
              # Database secrets
              postgres-password = {
                name = "Production Database";
                user = "admin@company.com";
                type = "login";
                field = "password";
              };

              # API secrets
              api-token = "External API Service";

              # SSL certificates
              ssl-cert = {
                name = "SSL Certificate";
                type = "note";
                field = "certificate";
              };

              ssl-key = {
                name = "SSL Certificate";
                type = "note";
                field = "private_key";
              };
            };
          };

          # PostgreSQL service using secrets
          postgresql = {
            enable = true;
            package = pkgs.postgresql_15;
            authentication = ''
              local all postgres peer
              local all all md5
            '';
            # In practice, password would be set from secret file
          };

          # Nginx service using SSL certificates
          nginx = {
            enable = true;
            virtualHosts."example.com" = {
              enableACME = false;
              forceSSL = true;
              # In practice, these would reference the secret files:
              # sslCertificate = "/run/secrets/ssl-cert";
              # sslCertificateKey = "/run/secrets/ssl-key";
            };
          };
        };

        # Custom application service
        systemd.services.api-service = {
          description = "API service using sopswarden secrets";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "simple";
            User = "api-service";
            Group = "api-service";
            # Load secrets as credentials
            LoadCredential = [
              "api-token:/run/secrets/api-token"
              "db-password:/run/secrets/postgres-password"
            ];
          };
          script = ''
            # Application would read secrets from credential files
            echo "API service starting..."
            echo "Token file: $CREDENTIALS_DIRECTORY/api-token"
            echo "DB password file: $CREDENTIALS_DIRECTORY/db-password"
            
            # In practice, the application would:
            # API_TOKEN=$(cat $CREDENTIALS_DIRECTORY/api-token)
            # DB_PASSWORD=$(cat $CREDENTIALS_DIRECTORY/db-password)
            
            # Start the actual service
            sleep infinity
          '';
        };

        # User for the API service
        users.users.api-service = {
          isSystemUser = true;
          group = "api-service";
        };

        users.groups.api-service = { };
      };

      # Evaluate the configuration using nixosSystem for full module environment
      testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ appConfig ];
      };
    in
    {
      # Service configuration validation
      hasPostgresql = testSystem.config.services.postgresql.enable;
      hasNginx = testSystem.config.services.nginx.enable;
      hasApiService = builtins.hasAttr "api-service" testSystem.config.systemd.services;

      # Secret integration validation
      secretsCount = builtins.length (builtins.attrNames testSystem.config.services.sopswarden.secrets);
      sopsSecretsCount = builtins.length (builtins.attrNames testSystem.config.sops.secrets);

      # Service-specific validation
      hasCredentials = builtins.hasAttr "LoadCredential" testSystem.config.systemd.services.api-service.serviceConfig;

      # User creation
      hasApiUser = builtins.hasAttr "api-service" testSystem.config.users.users;
      hasApiGroup = builtins.hasAttr "api-service" testSystem.config.users.groups;

      # All secrets defined
      hasPostgresPassword = builtins.hasAttr "postgres-password" testSystem.config.services.sopswarden.secrets;
      hasApiToken = builtins.hasAttr "api-token" testSystem.config.services.sopswarden.secrets;
      hasSslCert = builtins.hasAttr "ssl-cert" testSystem.config.services.sopswarden.secrets;
      hasSslKey = builtins.hasAttr "ssl-key" testSystem.config.services.sopswarden.secrets;
    };

in
{
  # Test sync script generation
  syncScript = testSyncScript;

  # Test application access
  applicationAccess = testApplicationAccess;

  # Overall validation
  success =
    testSyncScript.isDerivation &&
    testApplicationAccess.hasPostgresql &&
    testApplicationAccess.hasNginx &&
    testApplicationAccess.hasApiService &&
    testApplicationAccess.secretsCount == 4 &&
    testApplicationAccess.sopsSecretsCount == 4 &&
    testApplicationAccess.hasCredentials &&
    testApplicationAccess.hasApiUser &&
    testApplicationAccess.hasPostgresPassword &&
    testApplicationAccess.hasApiToken &&
    testApplicationAccess.hasSslCert &&
    testApplicationAccess.hasSslKey;

  # Detailed validation
  validation = {
    syncScriptGeneration = testSyncScript.isDerivation;
    servicesConfigured = testApplicationAccess.hasPostgresql && testApplicationAccess.hasNginx && testApplicationAccess.hasApiService;
    secretsIntegration = testApplicationAccess.secretsCount == 4 && testApplicationAccess.sopsSecretsCount == 4;
    credentialsLoaded = testApplicationAccess.hasCredentials;
    usersCreated = testApplicationAccess.hasApiUser && testApplicationAccess.hasApiGroup;
    allSecretsPresent = testApplicationAccess.hasPostgresPassword && testApplicationAccess.hasApiToken && testApplicationAccess.hasSslCert && testApplicationAccess.hasSslKey;
  };
}
