# File disabling module - prevents HM symlinks for SOPS-managed files
# This module runs after detection and disables the conflicting files

{ lib, config, ... }:

{
  # Import detection module first
  imports = [
    ./detect-templates.nix
  ];

  config = lib.mkMerge [
    # Only disable files if we actually detected some
    (lib.mkIf (config.sopswarden.detectedFiles != {}) {
      # Automatically disable Home Manager files that contain SOPS placeholders
      # This prevents conflicts between HM symlinks and SOPS-generated files
      # Using mkForce null for compatibility with all Home Manager versions
      home.file = lib.mapAttrs (_: _: lib.mkForce null) config.sopswarden.detectedFiles;

      # Provide informative warnings
      warnings = [
        "sopswarden: Detected ${toString (builtins.length (builtins.attrNames config.sopswarden.detectedFiles))} Home Manager files with SOPS placeholders: ${lib.concatStringsSep ", " (builtins.attrNames config.sopswarden.detectedFiles)}. Templates will be processed by SOPS during system activation. Home Manager symlinks disabled automatically via mkForce null."
      ];
    })
  ];
}