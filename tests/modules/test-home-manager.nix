# Test Home Manager module integration
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library and helpers
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };
  sopswardenHelpers = import ../../lib/secret.nix { lib = pkgs.lib; };
  
  # Test secrets configuration (what user would define)
  testSecrets = {
    git-username = "GitHub Account";
    git-email = "GitHub Email"; 
    ssh-key = { name = "SSH Key"; type = "note"; field = "private_key"; };
    api-token = "Development API";
  };
  
  # Mock SOPS configuration (what NixOS module would generate)
  mockSopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = testSecrets;
    sopsFile = "/var/lib/sopswarden/secrets.yaml";
  };
  
  mockConfig = {
    sops.secrets = builtins.mapAttrs (name: secretConfig: 
      secretConfig // { path = "/run/secrets/${name}"; }
    ) mockSopsSecrets;
  };
  
  # Generate secret accessors
  secretAccessors = sopswardenLib.mkSecretAccessors {
    config = mockConfig;
    secrets = testSecrets;
  };
  
  # Test Home Manager configurations using different approaches
  homeManagerConfigs = {
    
    # Approach 1: Traditional SOPS paths (files only)
    traditional = {
      programs.git = {
        enable = true;
        # These would use file paths - limited to services that support file input
        includes = [
          {
            condition = "gitdir:~/work/";
            contents = {
              user.name = builtins.readFile secretAccessors.git-username;  # Would fail in pure eval
              user.email = builtins.readFile secretAccessors.git-email;   # Would fail in pure eval
            };
          }
        ];
      };
    };
    
    # Approach 2: Sentinel-based (string values)
    sentinel = {
      programs.git = {
        enable = true;
        extraConfig = {
          user.name = sopswardenHelpers.secretString secretAccessors.git-username;   # "__SOPSWARDEN_GIT-USERNAME__"
          user.email = sopswardenHelpers.secretString secretAccessors.git-email;     # "__SOPSWARDEN_GIT-EMAIL__"
        };
      };
      
      programs.ssh = {
        enable = true;
        extraConfig = ''
          Host github.com
            HostName github.com
            IdentityFile ${sopswardenHelpers.secretString secretAccessors.ssh-key}
        '';
      };
      
      home.sessionVariables = {
        GITHUB_TOKEN = sopswardenHelpers.secretString secretAccessors.api-token;     # "__SOPSWARDEN_API-TOKEN__"
      };
      
      # Test file content substitution
      home.file.".netrc".text = ''
        machine api.github.com
        login myuser
        password ${sopswardenHelpers.secretString secretAccessors.api-token}
      '';
    };
    
    # Approach 3: Mixed usage (paths where supported, sentinels elsewhere)
    mixed = {
      programs.git = {
        enable = true;
        extraConfig = {
          # Use sentinels for direct values
          user.name = sopswardenHelpers.secretString secretAccessors.git-username;
          user.email = sopswardenHelpers.secretString secretAccessors.git-email;
        };
      };
      
      systemd.user.services.backup = {
        Unit.Description = "Backup service";
        Service = {
          # Use file paths for environment files  
          EnvironmentFile = secretAccessors.api-token;  # "/run/secrets/api-token"
          ExecStart = "/bin/backup";
        };
      };
    };
  };
  
  # Test sentinel generation
  expectedSentinels = {
    git-username = "__SOPSWARDEN_GIT-USERNAME__";
    git-email = "__SOPSWARDEN_GIT-EMAIL__";
    ssh-key = "__SOPSWARDEN_SSH-KEY__";
    api-token = "__SOPSWARDEN_API-TOKEN__";
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-home-manager-test";
  
  buildCommand = ''
    echo "🧪 Testing Home Manager integration..."
    
    # Test 1: Secret accessor generation for HM
    echo "📋 Test 1: Secret accessors for Home Manager"
    git_user_path="${secretAccessors.git-username}"
    git_email_path="${secretAccessors.git-email}"
    ssh_key_path="${secretAccessors.ssh-key}"
    api_token_path="${secretAccessors.api-token}"
    
    if [ "$git_user_path" = "/run/secrets/git-username" ] && \
       [ "$git_email_path" = "/run/secrets/git-email" ] && \
       [ "$ssh_key_path" = "/run/secrets/ssh-key" ] && \
       [ "$api_token_path" = "/run/secrets/api-token" ]; then
      echo "✅ Secret accessors generate correct paths for HM"
    else
      echo "❌ Secret accessor paths incorrect"
      echo "  Git user: $git_user_path"
      echo "  Git email: $git_email_path"
      echo "  SSH key: $ssh_key_path"
      echo "  API token: $api_token_path"
      exit 1
    fi
    
    # Test 2: Sentinel generation for HM configs
    echo "📋 Test 2: Sentinel generation for Home Manager"
    git_user_sentinel="${homeManagerConfigs.sentinel.programs.git.extraConfig.user.name}"
    git_email_sentinel="${homeManagerConfigs.sentinel.programs.git.extraConfig.user.email}"
    api_var_sentinel="${homeManagerConfigs.sentinel.home.sessionVariables.GITHUB_TOKEN}"
    
    if [ "$git_user_sentinel" = "${expectedSentinels.git-username}" ] && \
       [ "$git_email_sentinel" = "${expectedSentinels.git-email}" ] && \
       [ "$api_var_sentinel" = "${expectedSentinels.api-token}" ]; then
      echo "✅ Sentinel approach works in HM configs"
    else
      echo "❌ Sentinel generation failed in HM"
      echo "  Git user: got '$git_user_sentinel', expected '${expectedSentinels.git-username}'"
      echo "  Git email: got '$git_email_sentinel', expected '${expectedSentinels.git-email}'"
      echo "  API var: got '$api_var_sentinel', expected '${expectedSentinels.api-token}'"
      exit 1
    fi
    
    # Test 3: File content substitution
    echo "📋 Test 3: File content with sentinels"
    netrc_content="${homeManagerConfigs.sentinel.home.file.".netrc".text}"
    expected_line="password ${expectedSentinels.api-token}"
    
    if echo "$netrc_content" | grep -q "$expected_line"; then
      echo "✅ File content substitution works"
    else
      echo "❌ File content substitution failed"
      echo "  Content: $netrc_content"
      echo "  Expected to contain: $expected_line"
      exit 1
    fi
    
    # Test 4: SSH config substitution
    echo "📋 Test 4: SSH config with sentinels"
    ssh_config="${homeManagerConfigs.sentinel.programs.ssh.extraConfig}"
    expected_identity="IdentityFile ${expectedSentinels.ssh-key}"
    
    if echo "$ssh_config" | grep -q "$expected_identity"; then
      echo "✅ SSH config substitution works"
    else
      echo "❌ SSH config substitution failed"
      echo "  Config: $ssh_config"
      echo "  Expected to contain: $expected_identity"
      exit 1
    fi
    
    # Test 5: Mixed approach validation
    echo "📋 Test 5: Mixed approach (sentinels + paths)"
    mixed_git_user="${homeManagerConfigs.mixed.programs.git.extraConfig.user.name}"
    mixed_env_file="${homeManagerConfigs.mixed.systemd.user.services.backup.Service.EnvironmentFile}"
    
    if [ "$mixed_git_user" = "${expectedSentinels.git-username}" ] && \
       [ "$mixed_env_file" = "/run/secrets/api-token" ]; then
      echo "✅ Mixed approach works (sentinels for values, paths for files)"
    else
      echo "❌ Mixed approach failed"
      echo "  Git user: got '$mixed_git_user', expected '${expectedSentinels.git-username}'"
      echo "  Env file: got '$mixed_env_file', expected '/run/secrets/api-token'"
      exit 1
    fi
    
    echo ""
    echo "🎉 Home Manager integration test passed!"
    echo ""
    echo "📝 This validates Home Manager usage patterns:"
    echo "  ✓ programs.git.extraConfig with secret values"
    echo "  ✓ home.sessionVariables with secret tokens"
    echo "  ✓ home.file content with embedded secrets"
    echo "  ✓ programs.ssh.extraConfig with secret paths"
    echo "  ✓ systemd.user.services with environment files"
    echo "  ✓ Mixed approach: sentinels for values, paths for files"
    echo ""
    echo "🔍 Key insight: Sentinel approach enables Home Manager configs that"
    echo "   were impossible with file-only approach (git config, env vars, etc.)"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}