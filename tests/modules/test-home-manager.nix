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
    
    # Test 2: SOPS placeholder generation for HM configs
    echo "📋 Test 2: SOPS placeholder generation for Home Manager"
    
    # Write placeholder results to files to avoid bash expansion
    cat > git-user-placeholder << 'EOF'
${homeManagerConfigs.sentinel.programs.git.extraConfig.user.name}
EOF
    cat > git-email-placeholder << 'EOF'
${homeManagerConfigs.sentinel.programs.git.extraConfig.user.email}
EOF
    cat > api-var-placeholder << 'EOF'
${homeManagerConfigs.sentinel.home.sessionVariables.GITHUB_TOKEN}
EOF
    
    echo "Generated HM placeholder values:"
    echo "  Git user: $(cat git-user-placeholder)"
    echo "  Git email: $(cat git-email-placeholder)"
    echo "  API var: $(cat api-var-placeholder)"
    
    if grep -q "config.sops.placeholder.git-username" git-user-placeholder && \
       grep -q "config.sops.placeholder.git-email" git-email-placeholder && \
       grep -q "config.sops.placeholder.api-token" api-var-placeholder; then
      echo "✅ SOPS placeholder approach works in HM configs"
    else
      echo "❌ SOPS placeholder generation failed in HM"
      exit 1
    fi
    
    # Test 3: File content with SOPS placeholders
    echo "📋 Test 3: File content with SOPS placeholders"
    
    cat > netrc-content << 'EOF'
${homeManagerConfigs.sentinel.home.file.".netrc".text}
EOF
    
    echo "Generated .netrc content:"
    cat netrc-content
    
    if grep -q "config.sops.placeholder.api-token" netrc-content; then
      echo "✅ File content contains SOPS placeholders"
    else
      echo "❌ File content missing SOPS placeholders"
      exit 1
    fi
    
    # Test 4: SSH config with SOPS placeholders
    echo "📋 Test 4: SSH config with SOPS placeholders"
    
    cat > ssh-config << 'EOF'
${homeManagerConfigs.sentinel.programs.ssh.extraConfig}
EOF
    
    echo "Generated SSH config:"
    cat ssh-config
    
    if grep -q "config.sops.placeholder.ssh-key" ssh-config; then
      echo "✅ SSH config contains SOPS placeholders"
    else
      echo "❌ SSH config missing SOPS placeholders"
      exit 1
    fi
    
    # Test 5: Mixed approach validation
    echo "📋 Test 5: Mixed approach (placeholders + paths)"
    
    cat > mixed-git-user << 'EOF'
${homeManagerConfigs.mixed.programs.git.extraConfig.user.name}
EOF
    mixed_env_file="${homeManagerConfigs.mixed.systemd.user.services.backup.Service.EnvironmentFile}"
    
    echo "Mixed approach results:"
    echo "  Git user: $(cat mixed-git-user)"
    echo "  Env file: $mixed_env_file"
    
    if grep -q "config.sops.placeholder.git-username" mixed-git-user && \
       [ "$mixed_env_file" = "/run/secrets/api-token" ]; then
      echo "✅ Mixed approach works (placeholders for values, paths for files)"
    else
      echo "❌ Mixed approach failed"
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
    echo "🔍 Key insight: SOPS placeholder approach enables Home Manager configs that"
    echo "   were impossible with file-only approach (git config, env vars, etc.)"
    echo "   Uses native SOPS templates instead of custom rewrite scripts."
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}