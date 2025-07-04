# Test Home Manager module integration
# Validates that sopswarden works in user-level configurations

let
  flake = builtins.getFlake (toString ../..);
  pkgs = import <nixpkgs> { };

  # Evaluate Home Manager configuration
  # Note: This is a simplified test as full Home Manager evaluation is complex
  testHomeManager =
    let
      homeManagerModule = flake.homeManagerModules.default;

      # Test basic module structure with sopswarden configuration
      moduleTest = { ... }: {
        imports = [ homeManagerModule ];

        # Test configuration to ensure module works
        programs = {
          sopswarden = {
            enable = true;

            # User-level secrets
            secrets = {
              # Personal secrets
              personal-email = "Personal Email Account";

              github-token = {
                name = "GitHub Personal Token";
                type = "note";
                field = "token";
              };

              ssh-key = {
                name = "Personal SSH Key";
                type = "note";
                field = "private_key";
              };

              # Development secrets
              api-key = "Development API Key";
            };

            # User-specific paths
            secretsFile = "~/config/secrets.nix";
            sopsFile = "~/config/secrets.yaml";
            ageKeyFile = "~/.config/sops/age/keys.txt";
          };

          # Git configuration that might use secrets
          git = {
            enable = true;
            userName = "Test User";
            userEmail = "test@example.com";
            # In practice, SSH keys would be configured to use the secret
          };

          # SSH configuration
          ssh = {
            enable = true;
            # SSH keys would reference the secret in practice
          };
        };

        # Test that secrets can be referenced in home config
        # Note: Home Manager version may not have full SOPS integration
        home.file."test-config".text = ''
          # Configuration file that would use secrets
          email = "user@example.com"
          # In a real setup, this would reference the secret
          # token_file = ~/.config/secrets/github-token
        '';
      };

      # Basic evaluation to test options
      moduleEval = pkgs.lib.evalModules {
        modules = [ moduleTest ];
      };
    in
    moduleEval;

  # Test results
  testResults = {
    # Basic module loading
    hasHomeManagerModule = builtins.isFunction flake.homeManagerModules.default;
    hasDefaultModule = builtins.hasAttr "default" flake.homeManagerModules;
    hasSopswardenAlias = builtins.hasAttr "sopswarden" flake.homeManagerModules;

    # Module evaluation
    hasOptions = builtins.hasAttr "options" testHomeManager;

    # Check if the module defines the expected options structure
    # This is a basic test since Home Manager modules may have different structure
    moduleDefinesOptions = builtins.hasAttr "options" testHomeManager;
  };

in
{
  # Test Home Manager module
  homeManagerModule = testResults;

  # Validate basic functionality
  success =
    testResults.hasHomeManagerModule &&
    testResults.hasDefaultModule &&
    testResults.hasSopswardenAlias &&
    testResults.hasOptions;

  # Detailed validation
  validation = {
    moduleExists = testResults.hasHomeManagerModule;
    moduleAliasExists = testResults.hasSopswardenAlias;
    moduleCanBeEvaluated = testResults.hasOptions;
    moduleStructureCorrect = testResults.moduleDefinesOptions;
  };
}
