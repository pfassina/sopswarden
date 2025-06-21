{
  description = "Advanced sopswarden example with custom configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sopswarden.url = "github:pfassina/sopswarden";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sopswarden, home-manager, ... }: {
    nixosConfigurations.advanced = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sopswarden.nixosModules.default
        home-manager.nixosModules.home-manager
        ({ pkgs, config, secrets, ... }: {
          # Note: Configure rbw using Home Manager or manually:
          # programs.rbw = { enable = true; settings = { email = "..."; }; };

          # Advanced sopswarden configuration
          services.sopswarden = {
            enable = true;
            
            # Custom file locations
            secretsFile = ./config/secrets.nix;
            sopsFile = ./config/secrets.yaml;
            sopsConfigFile = ./config/.sops.yaml;
            
            # Custom rbw configuration (e.g., for self-hosted Bitwarden)
            rbwCommand = "${pkgs.rbw}/bin/rbw";
            
            # Custom ownership for secrets
            defaultOwner = "myuser";
            defaultGroup = "users";
            defaultMode = "0440";
            
            # Define secrets with various patterns
            secrets = {
              # Database cluster secrets
              postgres-master-password = { 
                name = "Database Cluster"; 
                user = "postgres@production.com";
              };
              postgres-replica-password = { 
                name = "Database Cluster"; 
                user = "replica@production.com"; 
              };
              
              # API keys for different environments
              api-key-production = { 
                name = "Service API"; 
                user = "production@company.com"; 
              };
              api-key-staging = { 
                name = "Service API"; 
                user = "staging@company.com"; 
              };
              
              # Network infrastructure
              vpn-config = {
                name = "Network Infrastructure";
                type = "note";
                field = "vpn_config";
              };
              
              # SSL certificates
              ssl-private-key = {
                name = "SSL Certificates";
                type = "note"; 
                field = "private_key";
              };
              ssl-certificate = {
                name = "SSL Certificates";
                type = "note";
                field = "certificate";
              };
              
              # Monitoring and alerting
              grafana-admin-password = "Grafana Admin";
              prometheus-remote-write-token = {
                name = "Monitoring";
                type = "note";
                field = "prometheus_token";
              };
              
              # Backup encryption
              restic-password = "Backup Encryption";
              
              # Email configuration
              smtp-password = {
                name = "Email Server";
                type = "note";
                field = "smtp_password";
              };
            };
          };

          # Example usage in NixOS configuration
          services = {
            # Database with secret
            postgresql = {
              enable = true;
              authentication = pkgs.lib.mkAfter ''
                host production_db postgres 10.0.0.0/8 md5
              '';
            };
            
            # Grafana with admin password
            grafana = {
              enable = true;
              settings.security.admin_password = "$__file{${config.sops.secrets.grafana-admin-password.path}}";
            };
            
            # Restic backup
            restic.backups.daily = {
              passwordFile = config.sops.secrets.restic-password.path;
              repository = "s3:backup-bucket/server";
              paths = [ "/home" "/etc" ];
            };
          };

          # Minimal system configuration
          system.stateVersion = "24.11";
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
          users.users.myuser = { isNormalUser = true; };

          # Home manager integration
          home-manager.users.myuser = {
            home.stateVersion = "24.11";
            # Configure rbw for the user
            programs.rbw = {
              enable = true;
              settings = {
                email = "admin@company.com";
                base_url = "https://vault.company.com";  # Self-hosted Bitwarden
                lock_timeout = 3600;
                pinentry = pkgs.pinentry-gtk2;
              };
            };
            
            # Note: programs.sopswarden would be available if homeManagerModules were imported
            # For now, sopswarden is configured at system level
          };

          # Custom deployment script that auto-syncs
          environment.systemPackages = with pkgs; [
            (writeShellScriptBin "deploy-with-secrets" ''
              #!/usr/bin/env bash
              set -euo pipefail
              
              echo "🔄 Syncing secrets from Bitwarden..."
              sopswarden-sync
              
              echo "🚀 Deploying system configuration..."
              sudo nixos-rebuild switch --flake .#advanced --impure
              
              echo "✅ Deployment complete!"
            '')
          ];
        })
      ];
    };
  };
}