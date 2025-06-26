# Home Manager SOPS template integration
# Uses two-module approach to avoid infinite recursion:
# 1. detect-templates.nix - detects files with SOPS placeholders
# 2. disable-files.nix - disables HM symlinks for those files

{ ... }:

{
  imports = [
    ./disable-files.nix
  ];

  # Note: Template processing now handled by NixOS module as root
  # Files will be written directly to final locations by SOPS
}