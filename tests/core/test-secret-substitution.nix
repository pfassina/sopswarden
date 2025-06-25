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
  
  # Test secretString function
  testSecretString = {
    git-username = sopswardenHelpers.secretString "/run/secrets/git-username";
    api-key = sopswardenHelpers.secretString "/run/secrets/api-key";
    database-password = sopswardenHelpers.secretString "/run/secrets/database-password";
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
    
    # New approach: secretString sentinels
    sentinel = {
      programs.git.extraConfig = {
        user.name = sopswardenHelpers.secretString secretAccessors.git-username;  # "__SOPSWARDEN_GIT-USERNAME__"
      };
      environment.variables = {
        API_KEY_FILE = sopswardenHelpers.secretString secretAccessors.api-key;    # "__SOPSWARDEN_API-KEY__"
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
    
    # Test 2: secretString function
    echo "📋 Test 2: secretString function"
    git_string="${testSecretString.git-username}"
    api_string="${testSecretString.api-key}"
    db_string="${testSecretString.database-password}"
    
    if [ "$git_string" = "$expected_git" ] && \
       [ "$api_string" = "$expected_api" ] && \
       [ "$db_string" = "$expected_db" ]; then
      echo "✅ secretString function works correctly"
    else
      echo "❌ secretString function failed"
      echo "  Git: got '$git_string', expected '$expected_git'"
      echo "  API: got '$api_string', expected '$expected_api'"
      echo "  DB: got '$db_string', expected '$expected_db'"
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
    
    # Sentinel approach should give sentinel tokens
    sent_git="${testConfigurations.sentinel.programs.git.extraConfig.user.name}"
    sent_api="${testConfigurations.sentinel.environment.variables.API_KEY_FILE}"
    
    if [ "$sent_git" = "__SOPSWARDEN_GIT-USERNAME__" ] && \
       [ "$sent_api" = "__SOPSWARDEN_API-KEY__" ]; then
      echo "✅ Sentinel approach: tokens work"
    else
      echo "❌ Sentinel approach failed"
      echo "  Git: got '$sent_git', expected '__SOPSWARDEN_GIT-USERNAME__'"
      echo "  API: got '$sent_api', expected '__SOPSWARDEN_API-KEY__'"
      exit 1
    fi
    
    # Test 4: Use case validation
    echo "📋 Test 4: Use case validation"
    echo ""
    echo "📝 Traditional approach (SOPS paths):"
    echo "  programs.git.extraConfig.user.name = secrets.git-username"
    echo "  → /run/secrets/git-username"
    echo ""
    echo "📝 Sentinel approach (runtime substitution):"
    echo "  programs.git.extraConfig.user.name = sopswarden.secretString secrets.git-username"
    echo "  → __SOPSWARDEN_GIT-USERNAME__ (at build time)"
    echo "  → actual secret content (at activation time)"
    echo ""
    
    echo "🎉 Secret substitution functionality test passed!"
    echo ""
    echo "🔍 This test validates:"
    echo "  ✓ Sentinel token generation (mkSentinel)"
    echo "  ✓ secretString function behavior"
    echo "  ✓ Dual approach compatibility"
    echo "  ✓ Configuration integration patterns"
    echo ""
    echo "⚠️  Missing: actual runtime substitution testing"
    echo "   (requires activation script execution)"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}