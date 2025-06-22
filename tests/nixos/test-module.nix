# NixOS module test configuration
{ config, pkgs, lib, ... }:

let
  # Import sopswarden module
  sopswardenModule = import ../../modules/nixos.nix { 
    inherit lib;
    sops-nix = {
      nixosModules.sops = { ... }: {
        options.sops = lib.mkOption {
          type = lib.types.attrs;
          default = {};
        };
        config.sops = {};
      };
    };
  };

in {
  imports = [ sopswardenModule ];

  # Test basic sopswarden configuration
  services.sopswarden = {
    enable = true;
    
    secrets = {
      test-secret = "Test Item";
      complex-secret = {
        name = "Complex Item";
        user = "test@example.com";
      };
      note-secret = {
        name = "Note Item";
        type = "note";
        field = "custom_field";
      };
    };
    
    # Test custom configuration
    defaultOwner = "testuser";
    defaultGroup = "testgroup";
    defaultMode = "0440";
    
    installPackages = true;
    enableChangeDetection = true;
  };

  # Verify that the module produces expected configuration
  system.build.test-sopswarden = pkgs.writeText "test-sopswarden" ''
    Testing sopswarden NixOS module configuration:
    
    Secrets configured: ${toString (builtins.attrNames config.services.sopswarden.secrets)}
    Default owner: ${config.services.sopswarden.defaultOwner}
    Default group: ${config.services.sopswarden.defaultGroup}
    Default mode: ${config.services.sopswarden.defaultMode}
    
    SOPS secrets: ${toString (builtins.attrNames config.sops.secrets)}
    
    Test: ${if config.services.sopswarden.enable then "PASS" else "FAIL"}
  '';
}