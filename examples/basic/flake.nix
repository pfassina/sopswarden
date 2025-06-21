{
  description = "Basic sopswarden example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sopswarden.url = "github:pfassina/sopswarden";
  };

  outputs = { self, nixpkgs, sopswarden, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sopswarden.nixosModules.default
        ({ pkgs, secrets, ... }: {
          # Configure rbw for Bitwarden access
          programs.rbw = {
            enable = true;
            settings = {
              email = "your-email@example.com";
              # base_url = "https://your-bitwarden-server.com";  # Uncomment for self-hosted
              lock_timeout = 3600;
              pinentry = pkgs.pinentry-curses;
            };
          };

          # Enable sopswarden
          services.sopswarden = {
            enable = true;
            
            # Define your secrets
            secrets = {
              # Simple secret (uses password field from login item)
              api-key = "My API Service";
              
              # Secret with specific user account  
              database-password = {
                name = "Database Server";
                user = "admin@example.com";
              };
              
              # Secret from secure note custom field
              wifi-password = {
                name = "Home WiFi";
                type = "note";
                field = "password";
              };
            };
          };

          # Example: Use secrets in your configuration
          networking.wireless.networks."MyNetwork" = {
            psk = secrets.wifi-password;
          };

          # Example: Configure a service with secret
          services.postgresql = {
            enable = true;
            authentication = pkgs.lib.mkAfter ''
              host myapp myuser 0.0.0.0/0 md5
            '';
          };
        })
      ];
    };
  };
}