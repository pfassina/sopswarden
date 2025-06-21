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
          # Note: Configure rbw using Home Manager or manually:
          # programs.rbw = { enable = true; settings = { email = "..."; }; };

          # Enable sopswarden
          services.sopswarden = {
            enable = true;
            
            # Use the included secrets.nix file
            secretsFile = ./secrets.nix;
            # Override hashFile for the example
            hashFile = "/tmp/sopswarden-basic-hash";
            
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

          # Minimal NixOS configuration for the example
          system.stateVersion = "24.11";
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
        })
      ];
    };
  };
}