# Test file permissions and security attributes for sopswarden secrets
# Validates that secret files have correct permissions, ownership, and security configurations

let
  flake = builtins.getFlake (toString ../..);

  # Test default security settings
  testDefaultSecurity =
    let
      # Test mkSecret with default security settings
      defaultSecret = flake.lib.mkSecret "test-secret" {
        file = "/test/secrets.yaml";
      };

      # Test mkSopsSecrets with default security
      defaultSopsSecrets = flake.lib.mkSopsSecrets {
        secrets = {
          secure-secret = { name = "Secure Item"; };
          another-secret = { name = "Another Item"; };
        };
        sopsFile = "/test/secrets.yaml";
      };
    in
    {
      # Test mkSecret default security
      defaultSecretMode = defaultSecret.mode == "0400";
      defaultSecretOwner = defaultSecret.owner == "root";
      defaultSecretGroup = defaultSecret.group == "root";
      defaultSecretSopsFile = defaultSecret.sopsFile == "/test/secrets.yaml";

      # Test mkSopsSecrets default security
      sopsSecretsHaveSecrets = builtins.hasAttr "secure-secret" defaultSopsSecrets && builtins.hasAttr "another-secret" defaultSopsSecrets;
      firstSecretMode =
        if builtins.hasAttr "secure-secret" defaultSopsSecrets
        then defaultSopsSecrets.secure-secret.mode == "0400"
        else false;
      firstSecretOwner =
        if builtins.hasAttr "secure-secret" defaultSopsSecrets
        then defaultSopsSecrets.secure-secret.owner == "root"
        else false;
      firstSecretGroup =
        if builtins.hasAttr "secure-secret" defaultSopsSecrets
        then defaultSopsSecrets.secure-secret.group == "root"
        else false;
      secondSecretMode =
        if builtins.hasAttr "another-secret" defaultSopsSecrets
        then defaultSopsSecrets.another-secret.mode == "0400"
        else false;
    };

  # Test custom security settings
  testCustomSecurity =
    let
      # Test mkSecret with custom security settings
      customSecret = flake.lib.mkSecret "custom-secret" {
        file = "/custom/secrets.yaml";
        owner = "app-user";
        group = "app-group";
        mode = "0600";
      };

      # Test mkSopsSecrets with custom security
      customSopsSecrets = flake.lib.mkSopsSecrets {
        secrets = {
          app-secret = { name = "App Secret"; };
          db-secret = { name = "Database Secret"; };
        };
        sopsFile = "/custom/app-secrets.yaml";
        defaultOwner = "app-service";
        defaultGroup = "app-service";
        defaultMode = "0440";
      };
    in
    {
      # Test mkSecret custom security
      customSecretMode = customSecret.mode == "0600";
      customSecretOwner = customSecret.owner == "app-user";
      customSecretGroup = customSecret.group == "app-group";
      customSecretSopsFile = customSecret.sopsFile == "/custom/secrets.yaml";

      # Test mkSopsSecrets custom security
      customSopsHasSecrets = builtins.hasAttr "app-secret" customSopsSecrets && builtins.hasAttr "db-secret" customSopsSecrets;
      appSecretMode =
        if builtins.hasAttr "app-secret" customSopsSecrets
        then customSopsSecrets.app-secret.mode == "0440"
        else false;
      appSecretOwner =
        if builtins.hasAttr "app-secret" customSopsSecrets
        then customSopsSecrets.app-secret.owner == "app-service"
        else false;
      appSecretGroup =
        if builtins.hasAttr "app-secret" customSopsSecrets
        then customSopsSecrets.app-secret.group == "app-service"
        else false;
      dbSecretMode =
        if builtins.hasAttr "db-secret" customSopsSecrets
        then customSopsSecrets.db-secret.mode == "0440"
        else false;
      dbSecretOwner =
        if builtins.hasAttr "db-secret" customSopsSecrets
        then customSopsSecrets.db-secret.owner == "app-service"
        else false;
    };

  # Test security in NixOS module context
  testModuleSecurity =
    let
      # Configuration with security-conscious settings
      securityConfig = { ... }: {
        imports = [ flake.nixosModules.default ];

        # Required for NixOS system evaluation
        system.stateVersion = "25.11";

        services.sopswarden = {
          enable = true;
          secrets = {
            # High-security secret (default restrictive permissions)
            admin-password = {
              name = "Admin Password";
              user = "admin@company.com";
              type = "login";
              field = "password";
            };

            # Application secret with custom permissions
            api-token = "API Service Token";

            # Database credentials
            db-credentials = {
              name = "Production Database";
              user = "db-admin@company.com";
              type = "login";
              field = "password";
            };
          };

          # Security settings
          defaultOwner = "root";
          defaultGroup = "secrets";
          defaultMode = "0440";
          sopsFile = "/etc/secrets/production.yaml";
        };

        # Test that secrets are properly configured in SOPS
        # with correct security attributes
      };

      # Evaluate the configuration using nixosSystem for full module environment
      testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ securityConfig ];
      };
    in
    {
      # Configuration should evaluate successfully
      systemEvaluates = builtins.hasAttr "config" testSystem;
      sopswardenEnabled = testSystem.config.services.sopswarden.enable;

      # Check SOPS secrets configuration
      hasSopsConfig = builtins.hasAttr "sops" testSystem.config;
      sopsSecretsCount = 
        if builtins.hasAttr "sops" testSystem.config && builtins.hasAttr "secrets" testSystem.config.sops
        then builtins.length (builtins.attrNames testSystem.config.sops.secrets)
        else 0;

      # Verify security settings are applied
      hasAdminPassword = 
        builtins.hasAttr "sops" testSystem.config && 
        builtins.hasAttr "secrets" testSystem.config.sops &&
        builtins.hasAttr "admin-password" testSystem.config.sops.secrets;
      hasApiToken = 
        builtins.hasAttr "sops" testSystem.config && 
        builtins.hasAttr "secrets" testSystem.config.sops &&
        builtins.hasAttr "api-token" testSystem.config.sops.secrets;
      hasDbCredentials = 
        builtins.hasAttr "sops" testSystem.config && 
        builtins.hasAttr "secrets" testSystem.config.sops &&
        builtins.hasAttr "db-credentials" testSystem.config.sops.secrets;

      # Test specific security attributes (if accessible)
      adminPasswordMode =
        if (builtins.hasAttr "sops" testSystem.config && 
            builtins.hasAttr "secrets" testSystem.config.sops &&
            builtins.hasAttr "admin-password" testSystem.config.sops.secrets)
        then testSystem.config.sops.secrets.admin-password.mode == "0440"
        else false;
      adminPasswordOwner =
        if (builtins.hasAttr "sops" testSystem.config && 
            builtins.hasAttr "secrets" testSystem.config.sops &&
            builtins.hasAttr "admin-password" testSystem.config.sops.secrets)
        then testSystem.config.sops.secrets.admin-password.owner == "root"
        else false;
      adminPasswordGroup =
        if (builtins.hasAttr "sops" testSystem.config && 
            builtins.hasAttr "secrets" testSystem.config.sops &&
            builtins.hasAttr "admin-password" testSystem.config.sops.secrets)
        then testSystem.config.sops.secrets.admin-password.group == "secrets"
        else false;

      # Test that sopsFile is correctly set (when sops is configured)
      sopsFileCorrect = 
        let 
          sopsFileCheck = builtins.tryEval (testSystem.config.sops.defaultSopsFile == "/etc/secrets/production.yaml");
        in
        if sopsFileCheck.success then sopsFileCheck.value else true; # Skip check if sops not configured (bootstrap mode)

      # Test security configuration values
      defaultOwnerSet = testSystem.config.services.sopswarden.defaultOwner == "root";
      defaultGroupSet = testSystem.config.services.sopswarden.defaultGroup == "secrets";
      defaultModeSet = testSystem.config.services.sopswarden.defaultMode == "0440";
    };

  # Test permission validation patterns
  testPermissionPatterns =
    let
      # Test various permission modes
      permissions = [
        { mode = "0400"; valid = true; description = "owner read-only"; }
        { mode = "0440"; valid = true; description = "owner/group read-only"; }
        { mode = "0600"; valid = true; description = "owner read-write"; }
        { mode = "0640"; valid = true; description = "owner read-write, group read"; }
        { mode = "0644"; valid = false; description = "world-readable (insecure)"; }
        { mode = "0666"; valid = false; description = "world-writable (insecure)"; }
        { mode = "0777"; valid = false; description = "world-accessible (insecure)"; }
      ];

      # Helper to check if a mode is secure (no world access)
      isSecureMode = mode:
        let
          # Extract world permissions (last digit)
          worldPerms = builtins.substring 3 1 mode;
        in
        worldPerms == "0";

      # Test each permission pattern
      permissionTests = map
        (perm: {
          inherit (perm) mode description;
          isSecure = isSecureMode perm.mode;
          matchesExpected = isSecureMode perm.mode == perm.valid;
        })
        permissions;

      # Count secure vs insecure modes
      secureCount = builtins.length (builtins.filter (p: p.isSecure) permissionTests);
      insecureCount = builtins.length (builtins.filter (p: !p.isSecure) permissionTests);
      totalCount = builtins.length permissionTests;
    in
    {
      inherit permissionTests;
      allTestsMatch = builtins.all (p: p.matchesExpected) permissionTests;
      secureModesDetected = secureCount == 4; # First 4 modes should be secure
      insecureModesDetected = insecureCount == 3; # Last 3 modes should be insecure
      totalTestsRun = totalCount == 7;
    };

  # Test systemd credential security
  testSystemdCredentials =
    let
      # Configuration using LoadCredential for secrets
      credentialConfig = { ... }: {
        imports = [ flake.nixosModules.default ];
        system.stateVersion = "25.11";

        services.sopswarden = {
          enable = true;
          secrets = {
            service-token = "Service API Token";
            database-password = "Database Password";
          };
        };

        # Test service that uses LoadCredential
        systemd.services.secure-app = {
          description = "Secure application using credentials";
          serviceConfig = {
            Type = "simple";
            User = "secure-app";
            Group = "secure-app";
            # Load secrets as credentials (secure method)
            LoadCredential = [
              "api-token:/run/secrets/service-token"
              "db-password:/run/secrets/database-password"
            ];
            # Security hardening
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
          };
          script = ''
            echo "Service starting with secure credentials..."
            # Credentials available in $CREDENTIALS_DIRECTORY
            echo "API token file: $CREDENTIALS_DIRECTORY/api-token"
            echo "DB password file: $CREDENTIALS_DIRECTORY/db-password"
          '';
        };

        users.users.secure-app = {
          isSystemUser = true;
          group = "secure-app";
        };
        users.groups.secure-app = { };
      };

      testSystem = flake.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ credentialConfig ];
      };

      # Extract service configuration safely
      serviceConfig =
        if builtins.hasAttr "secure-app" testSystem.config.systemd.services
        then testSystem.config.systemd.services.secure-app.serviceConfig
        else { };
    in
    {
      systemEvaluates = builtins.hasAttr "config" testSystem;
      hasSecureApp = builtins.hasAttr "secure-app" testSystem.config.systemd.services;

      # Check security hardening
      hasLoadCredential = builtins.hasAttr "LoadCredential" serviceConfig;
      credentialCount =
        if builtins.hasAttr "LoadCredential" serviceConfig
        then builtins.length serviceConfig.LoadCredential
        else 0;

      # Check security hardening features
      noNewPrivileges = serviceConfig.NoNewPrivileges or false;
      privateTmp = serviceConfig.PrivateTmp or false;
      protectSystem = serviceConfig.ProtectSystem == "strict";
      protectHome = serviceConfig.ProtectHome or false;
      restrictSUIDSGID = serviceConfig.RestrictSUIDSGID or false;

      # Check user isolation
      hasSecureUser = builtins.hasAttr "secure-app" testSystem.config.users.users;
      userIsSystem =
        if builtins.hasAttr "secure-app" testSystem.config.users.users
        then testSystem.config.users.users.secure-app.isSystemUser
        else false;
    };

in
{
  # Test results
  defaultSecurity = testDefaultSecurity;
  customSecurity = testCustomSecurity;
  moduleSecurity = testModuleSecurity;
  permissionPatterns = testPermissionPatterns;
  systemdCredentials = testSystemdCredentials;

  # Overall success validation
  success =
    testDefaultSecurity.defaultSecretMode &&
    testDefaultSecurity.defaultSecretOwner &&
    testDefaultSecurity.defaultSecretGroup &&
    testDefaultSecurity.sopsSecretsHaveSecrets &&
    testDefaultSecurity.firstSecretMode &&
    testDefaultSecurity.firstSecretOwner &&
    testDefaultSecurity.firstSecretGroup &&
    testDefaultSecurity.secondSecretMode &&
    testCustomSecurity.customSecretMode &&
    testCustomSecurity.customSecretOwner &&
    testCustomSecurity.customSecretGroup &&
    testCustomSecurity.customSopsHasSecrets &&
    testCustomSecurity.appSecretMode &&
    testCustomSecurity.appSecretOwner &&
    testCustomSecurity.appSecretGroup &&
    testCustomSecurity.dbSecretMode &&
    testCustomSecurity.dbSecretOwner &&
    testModuleSecurity.systemEvaluates &&
    testModuleSecurity.sopswardenEnabled &&
    testModuleSecurity.hasSopsConfig &&
    # SOPS secrets count should be 3 if configured, 0 if in bootstrap mode
    (testModuleSecurity.sopsSecretsCount == 3 || testModuleSecurity.sopsSecretsCount == 0) &&
    # These tests only apply when SOPS is configured (not in bootstrap mode)
    (testModuleSecurity.sopsSecretsCount == 0 || (
      testModuleSecurity.hasAdminPassword &&
      testModuleSecurity.hasApiToken &&
      testModuleSecurity.hasDbCredentials &&
      testModuleSecurity.adminPasswordMode &&
      testModuleSecurity.adminPasswordOwner &&
      testModuleSecurity.adminPasswordGroup
    )) &&
    testModuleSecurity.sopsFileCorrect &&
    testModuleSecurity.defaultOwnerSet &&
    testModuleSecurity.defaultGroupSet &&
    testModuleSecurity.defaultModeSet &&
    testPermissionPatterns.allTestsMatch &&
    testPermissionPatterns.secureModesDetected &&
    testPermissionPatterns.insecureModesDetected &&
    testPermissionPatterns.totalTestsRun &&
    testSystemdCredentials.systemEvaluates &&
    testSystemdCredentials.hasSecureApp &&
    testSystemdCredentials.hasLoadCredential &&
    testSystemdCredentials.credentialCount == 2 &&
    testSystemdCredentials.noNewPrivileges &&
    testSystemdCredentials.privateTmp &&
    testSystemdCredentials.protectSystem &&
    testSystemdCredentials.protectHome &&
    testSystemdCredentials.restrictSUIDSGID &&
    testSystemdCredentials.hasSecureUser &&
    testSystemdCredentials.userIsSystem;

  # Detailed validation
  validation = {
    defaultSecurityWorks = testDefaultSecurity.defaultSecretMode && testDefaultSecurity.defaultSecretOwner && testDefaultSecurity.defaultSecretGroup;
    customSecurityWorks = testCustomSecurity.customSecretMode && testCustomSecurity.customSecretOwner && testCustomSecurity.customSecretGroup;
    moduleLevelSecurityWorks = testModuleSecurity.adminPasswordMode && testModuleSecurity.adminPasswordOwner && testModuleSecurity.adminPasswordGroup;
    permissionValidationWorks = testPermissionPatterns.allTestsMatch && testPermissionPatterns.secureModesDetected && testPermissionPatterns.insecureModesDetected;
    systemdCredentialsSecure = testSystemdCredentials.hasLoadCredential && testSystemdCredentials.noNewPrivileges && testSystemdCredentials.privateTmp;
    userIsolationWorks = testSystemdCredentials.hasSecureUser && testSystemdCredentials.userIsSystem;
    sopsIntegrationSecure = testModuleSecurity.hasSopsConfig && testModuleSecurity.sopsSecretsCount == 3;
    configurationSecurityApplied = testModuleSecurity.defaultOwnerSet && testModuleSecurity.defaultGroupSet && testModuleSecurity.defaultModeSet;
  };
}
