# Shared options for sopswarden that are visible to both NixOS and Home Manager modules
{ lib, ... }:

{
  options.sopswarden.hmTemplates = lib.mkOption {
    description = "SOPS-rendered templates that must end up in the user's home";
    type = with lib.types; attrsOf (submodule {
      options = {
        content = lib.mkOption {
          type = lib.types.str;
          description = "Template content with SOPS placeholders";
        };
        owner = lib.mkOption {
          type = lib.types.str;
          description = "File owner";
        };
        group = lib.mkOption {
          type = lib.types.str;
          description = "File group";
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0600";
          description = "File permissions";
        };
      };
    });
    default = {};
  };
}