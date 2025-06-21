{ lib }:

{ config, pkgs, ... }:

let
  inherit (lib) types mkOption mkEnableOption mkIf;
  cfg = config.programs.sopswarden;
  sopswardenLib = import ../lib { nixpkgs = lib; };

  # Create the sync script with user configuration
  syncScript = sopswardenLib.mkSyncScript {
    inherit (cfg) rbwCommand secretsFile sopsFile ageKeyFile sopsConfigFile workingDirectory;
    inherit pkgs;
  };

in
{
  options.programs.sopswarden = {
    enable = mkEnableOption "sopswarden secrets management for home-manager";

    # Core configuration
    secretsFile = mkOption {
      type = types.path;
      default = ./secrets.nix;
      description = "Path to the secrets.nix file containing secret definitions";
    };

    sopsFile = mkOption {
      type = types.path;
      default = ./secrets.yaml;
      description = "Path to the encrypted SOPS file";
    };

    ageKeyFile = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      description = "Path to the age private key file";
    };

    sopsConfigFile = mkOption {
      type = types.path;
      default = ./.sops.yaml;
      description = "Path to the .sops.yaml configuration file";
    };

    workingDirectory = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Working directory for sync operations. If null, uses directory containing secretsFile";
    };

    # rbw configuration
    rbwPackage = mkOption {
      type = types.package;
      default = pkgs.rbw;
      description = "rbw package to use for Bitwarden access";
    };

    rbwCommand = mkOption {
      type = types.str;
      default = "${cfg.rbwPackage}/bin/rbw";
      description = "Full command to use for rbw operations";
    };

    # Package management
    installPackages = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to install sopswarden dependencies in user environment";
    };
  };

  config = mkIf cfg.enable {
    home.packages = mkIf cfg.installPackages (
      (sopswardenLib.defaultPackages pkgs) ++ [ syncScript ]
    );
  };
}