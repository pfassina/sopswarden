# Test SOPS template workflow with Home Manager
{ pkgs ? import <nixpkgs> {} }:

let
  # Import sopswarden library
  sopswardenLib = import ../../lib { nixpkgs = pkgs.lib; };
  sopswardenHelpers = import ../../lib/secret.nix { lib = pkgs.lib; };
  
  # Test secrets configuration
  testSecrets = {
    git-username = "Git Username";
    git-email = "Git Email";
    ssh-key = "SSH Private Key";
  };
  
  # Mock SOPS configuration
  mockSopsSecrets = sopswardenLib.mkSopsSecrets {
    secrets = testSecrets;
    sopsFile = "/test/secrets.yaml";
  };
  
  mockConfig = {
    sops.secrets = builtins.mapAttrs (name: secretConfig: 
      secretConfig // { path = "/run/secrets/${name}"; }
    ) mockSopsSecrets;
  };
  
  # Generate secret accessors (traditional approach)
  secretAccessors = sopswardenLib.mkSecretAccessors {
    config = mockConfig;
    secrets = testSecrets;
  };
  
  # Test Home Manager configuration using SOPS placeholders
  homeManagerConfig = {
    # Git configuration with SOPS placeholders
    programs.git = {
      enable = true;
      extraConfig = {
        user.name = sopswardenHelpers.secretString secretAccessors.git-username;
        user.email = sopswardenHelpers.secretString secretAccessors.git-email;
      };
    };
    
    # SSH configuration with SOPS placeholders  
    programs.ssh = {
      enable = true;
      extraConfig = ''
        Host example
          HostName example.com
          IdentityFile ${sopswardenHelpers.secretString secretAccessors.ssh-key}
      '';
    };
    
    # Environment variables with SOPS placeholders
    home.sessionVariables = {
      GIT_AUTHOR_NAME = sopswardenHelpers.secretString secretAccessors.git-username;
      GIT_AUTHOR_EMAIL = sopswardenHelpers.secretString secretAccessors.git-email;
    };
  };
  
  # Extract the generated config text that would be written to files
  gitConfigText = ''
    [user]
      email = ${homeManagerConfig.programs.git.extraConfig.user.email}
      name = ${homeManagerConfig.programs.git.extraConfig.user.name}
  '';
  
  sshConfigText = homeManagerConfig.programs.ssh.extraConfig;
  
  # Test what the SOPS placeholders look like
  testPlaceholders = {
    gitName = homeManagerConfig.programs.git.extraConfig.user.name;
    gitEmail = homeManagerConfig.programs.git.extraConfig.user.email;
    sshKey = sopswardenHelpers.secretString secretAccessors.ssh-key;
  };

in pkgs.stdenv.mkDerivation {
  name = "sopswarden-sops-template-workflow-test-v2";
  
  buildCommand = ''
    echo "🧪 Testing SOPS template workflow..."
    
    # Test 1: Verify SOPS placeholders are generated
    echo "📋 Test 1: SOPS placeholder generation"
    
    # Write placeholders to files using cat to avoid bash expansion 
    cat > git-name-placeholder << 'EOF'
${testPlaceholders.gitName}
EOF
    cat > git-email-placeholder << 'EOF'
${testPlaceholders.gitEmail}
EOF
    cat > ssh-key-placeholder << 'EOF'
${testPlaceholders.sshKey}
EOF
    
    echo "Generated placeholder files for inspection"
    
    # Test 2: Verify config file generation would work
    echo "📋 Test 2: Config file content with placeholders"
    
    echo "Generated git config content:"
    cat > test-git-config << 'EOF'
${gitConfigText}
EOF
    cat test-git-config
    echo ""
    
    echo "Generated SSH config content:"
    cat > test-ssh-config << 'EOF'
${sshConfigText}
EOF
    cat test-ssh-config
    echo ""
    
    # Test 3: Verify placeholders follow SOPS format
    echo "📋 Test 3: SOPS placeholder format validation"
    
    # Check that all placeholders follow the expected SOPS format
    if grep -q "config.sops.placeholder" test-git-config && \
       grep -q "config.sops.placeholder" test-ssh-config; then
      echo "✅ SOPS placeholders found in generated configs"
    else
      echo "❌ SOPS placeholders not found in configs"
      exit 1
    fi
    
    # Test 4: Validate specific secret names
    echo "📋 Test 4: Secret name validation"
    
    if grep -q "git-username" test-git-config && \
       grep -q "git-email" test-git-config && \
       grep -q "ssh-key" test-ssh-config; then
      echo "✅ All expected secret names found in placeholders"
    else
      echo "❌ Missing expected secret names"
      exit 1
    fi
    
    echo ""
    echo "🎉 SOPS template workflow test passed!"
    echo ""
    echo "📝 This validates the new approach:"
    echo "  ✓ sopswarden.secretString emits SOPS placeholders"
    echo "  ✓ Home Manager configs contain \''${config.sops.placeholder.NAME}"
    echo "  ✓ Config files ready for SOPS template processing"
    echo "  ✓ No sentinel tokens or custom activation scripts needed"
    echo ""
    echo "🚀 Next: Integrate with actual SOPS template system"
    
    mkdir -p $out
    echo "success" > $out/result
  '';
}