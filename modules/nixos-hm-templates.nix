# NixOS module to process Home Manager SOPS templates
# This runs as root during system activation and writes files directly to user's home

{ lib, config, ... }:

let
  cfg = config.services.sopswarden;
  user = cfg.defaultOwner;
  
  # Get Home Manager templates if available
  hmTemplates = config.home-manager.users.${user}.sopswarden.hmTemplates or {};
  
in {
  imports = [
    ./shared.nix
  ];

  # Only create SOPS templates if Home Manager exported some
  config = lib.mkIf (cfg.enable && cfg.enableHmIntegration && hmTemplates != {}) {
    sops.templates = lib.mapAttrs'
      (relPath: tmpl: lib.nameValuePair "hm-${lib.strings.escapeNixIdentifier relPath}" (
        tmpl // {
          # Write directly to user's home directory with proper ownership
          path = "${config.users.users.${user}.home}/${relPath}";
        }
      ))
      hmTemplates;
  };
}