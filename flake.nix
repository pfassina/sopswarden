{
  description = "Sopswarden - SOPS secrets management integrated with Bitwarden";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, sops-nix }:
    let
      lib = import ./lib { nixpkgs = nixpkgs.lib; };
    in
    {
      # Library functions for other flakes to use
      lib = lib // {
        # Export the main library functions
        inherit (lib) mkSyncScript mkSopsSecrets mkSecretAccessors normalizeSecretDef;
        # Helper factory - users call this with their lib and config
        mkSopsWardenHelpers = { lib, config }: import ./lib/secret.nix { inherit lib config; };
      };

      # NixOS modules
      nixosModules = {
        default = import ./modules/nixos.nix { lib = nixpkgs.lib; inherit sops-nix; };
        sopswarden = self.nixosModules.default;
      };

      # Home Manager modules (optional)
      homeManagerModules = {
        default = import ./modules/home-manager.nix { lib = nixpkgs.lib; };
        sopswarden = self.homeManagerModules.default;
      };

      # Overlay for packages
      overlays.default = final: prev: {
        sopswarden-sync = lib.mkSyncScript {
          pkgs = final;
          # Default configuration - users can override
        };
      };

    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixpkgs-fmt
            statix
            deadnix
            sops
            age
            jq
          ];
        };

        # Packages for direct installation
        packages = {
          default = self.packages.${system}.sopswarden-sync;
          sopswarden-sync = lib.mkSyncScript { inherit pkgs; };
          sopswarden-bootstrap = pkgs.writeShellApplication {
            name = "sopswarden-bootstrap";
            runtimeInputs = with pkgs; [ rbw sops age jq nix ];
            text = builtins.readFile ./scripts/bootstrap.sh;
          };
        };

        # Apps for nix run  
        apps.sopswarden-bootstrap = {
          type = "app";
          program = "${self.packages.${system}.sopswarden-sync}/bin/sopswarden-sync";
        };

        # Checks for CI
        checks = {
          nixpkgs-fmt = pkgs.runCommand "nixpkgs-fmt-check" {} ''
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
            touch $out
          '';
        };
      }
    );
}