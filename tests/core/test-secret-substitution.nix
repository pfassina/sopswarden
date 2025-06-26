# Test secret substitution functionality (secretString sentinels)
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };
  sopswardenHelpers = import ../../lib/secret.nix { lib = pkgs.lib; };
  
  # Test secrets
  testSecrets = {
    git-username = "GitHub Account";
    api-key = "My Service API";
    database-password = { name = "DB Server"; user = "admin"; };
  };
  
  # Test sentinel generation
  testSentinels = {
    git-username = sopswardenHelpers.mkSentinel "git-username";
    api-key = sopswardenHelpers.mkSentinel "api-key";
    database-password = sopswardenHelpers.mkSentinel "database-password";
  };
  
  # Test secretString function (now produces SOPS placeholders)
  testSecretString = {
    git-username = sopswardenHelpers.secretString "/run/secrets/git-username";
    api-key = sopswardenHelpers.secretString "/run/secrets/api-key";
    database-password = sopswardenHelpers.secretString "/run/secrets/database-password";
  };
  
  # Expected SOPS placeholder patterns (for testing)
  expectedPlaceholders = {
    git-username = "\${config.sops.placeholder.git-username}";
    api-key = "\${config.sops.placeholder.api-key}";
    database-password = "\${config.sops.placeholder.database-password}";
  };
  
  # Mock config for secretAccessors (traditional approach)
  mockConfig = {
    sops.secrets = {
      git-username = { path = "/run/secrets/git-username"; };
      api-key = { path = "/run/secrets/api-key"; };
      database-password = { path = "/run/secrets/database-password"; };
    };
  };
  
  secretAccessors = sopswardenLib.mkSecretAccessors {
    config = mockConfig;
    secrets = testSecrets;
  };
  
  # Test configuration using both approaches
  testConfigurations = {
    # Traditional approach: direct SOPS paths
    traditional = {
      programs.git.extraConfig = {
        user.name = secretAccessors.git-username;  # "/run/secrets/git-username"
      };
      environment.variables = {
        API_KEY_FILE = secretAccessors.api-key;    # "/run/secrets/api-key"
      };
    };
    
    # New approach: secretString SOPS placeholders
    placeholder = {
      programs.git.extraConfig = {
        user.name = sopswardenHelpers.secretString secretAccessors.git-username;  # "${config.sops.placeholder.git-username}"
      };
      environment.variables = {
        API_KEY_FILE = sopswardenHelpers.secretString secretAccessors.api-key;    # "${config.sops.placeholder.api-key}"
      };
    };
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-secret-substitution-test";
  
  buildCommand = ''
    echo "🧪 Testing secret substitution functionality..."
    
    # Test 1: Sentinel generation
    echo "📋 Test 1: Sentinel generation"
    git_sentinel="${testSentinels.git-username}"
    api_sentinel="${testSentinels.api-key}"
    db_sentinel="${testSentinels.database-password}"
    
    expected_git="__SOPSWARDEN_GIT-USERNAME__"
    expected_api="__SOPSWARDEN_API-KEY__"
    expected_db="__SOPSWARDEN_DATABASE-PASSWORD__"
    
    if [ "$git_sentinel" = "$expected_git" ] && \
       [ "$api_sentinel" = "$expected_api" ] && \
       [ "$db_sentinel" = "$expected_db" ]; then
      echo "✅ Sentinel generation works correctly"
    else
      echo "❌ Sentinel generation failed"
      echo "  Git: got '$git_sentinel', expected '$expected_git'"
      echo "  API: got '$api_sentinel', expected '$expected_api'"
      echo "  DB: got '$db_sentinel', expected '$expected_db'"
      exit 1
    fi
    
    # Test 2: secretString function (SOPS placeholders)
    echo "📋 Test 2: secretString function (SOPS placeholders)"
    
    # Write placeholders to files to avoid bash expansion issues
    cat > git-placeholder << 'EOF'
${testSecretString.git-username}
EOF
    cat > api-placeholder << 'EOF'
${testSecretString.api-key}
EOF
    cat > db-placeholder << 'EOF'
${testSecretString.database-password}
EOF
    
    echo "Generated placeholder files:"
    echo "  Git: $(cat git-placeholder)"
    echo "  API: $(cat api-placeholder)"
    echo "  DB: $(cat db-placeholder)"
    
    # Test that placeholders contain the expected SOPS format
    if grep -q "config.sops.placeholder.git-username" git-placeholder && \
       grep -q "config.sops.placeholder.api-key" api-placeholder && \
       grep -q "config.sops.placeholder.database-password" db-placeholder; then
      echo "✅ secretString function produces SOPS placeholders"
    else
      echo "❌ secretString function failed to produce SOPS placeholders"
      exit 1
    fi
    
    # Test 3: Configuration approaches comparison
    echo "📋 Test 3: Configuration approaches"
    
    # Traditional approach should give SOPS paths
    trad_git="${testConfigurations.traditional.programs.git.extraConfig.user.name}"
    trad_api="${testConfigurations.traditional.environment.variables.API_KEY_FILE}"
    
    if [ "$trad_git" = "/run/secrets/git-username" ] && \
       [ "$trad_api" = "/run/secrets/api-key" ]; then
      echo "✅ Traditional approach: SOPS paths work"
    else
      echo "❌ Traditional approach failed"
      echo "  Git: got '$trad_git', expected '/run/secrets/git-username'"
      echo "  API: got '$trad_api', expected '/run/secrets/api-key'"
      exit 1
    fi
    
    # Placeholder approach should give SOPS placeholders
    cat > place-git << 'EOF'
${testConfigurations.placeholder.programs.git.extraConfig.user.name}
EOF
    cat > place-api << 'EOF'
${testConfigurations.placeholder.environment.variables.API_KEY_FILE}
EOF
    
    echo "Placeholder config results:"
    echo "  Git: $(cat place-git)"
    echo "  API: $(cat place-api)"
    
    if grep -q "config.sops.placeholder.git-username" place-git && \
       grep -q "config.sops.placeholder.api-key" place-api; then
      echo "✅ Placeholder approach: SOPS placeholders work in configs"
    else
      echo "❌ Placeholder approach failed in configs"
      exit 1
    fi
    
    # Test 4: Use case validation
    echo "📋 Test 4: Use case validation"
    echo ""
    echo "📝 Traditional approach (SOPS paths):"
    echo "  programs.git.extraConfig.user.name = secrets.git-username"
    echo "  → /run/secrets/git-username"
    echo ""
    echo "📝 SOPS placeholder approach (template resolution):"
    echo "  programs.git.extraConfig.user.name = sopswarden.secretString secrets.git-username"
    echo "  → \''${config.sops.placeholder.git-username} (at build time)"
    echo "  → actual secret content (via SOPS templates)"
    echo ""
    
    echo "🎉 Secret substitution functionality test passed!"
    echo ""
    echo "🔍 This test validates:"
    echo "  ✓ Legacy sentinel token generation (mkSentinel)"
    echo "  ✓ Traditional SOPS path approach (secrets.secret-name)"
    echo "  ✓ Basic function compatibility"
    echo ""
    echo "📝 Note: SOPS placeholder testing moved to dedicated integration tests"
    echo "   See: test-sops-template-workflow.nix and test-hm-template-integration.nix"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}