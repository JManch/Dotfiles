{ lib, pkgs', config, ... }:
let
  cfg = config.modules.programs.filenDesktop;
in
lib.mkIf cfg.enable
{
  home.packages = [ pkgs'.filen-desktop ];

  desktop.hyprland.settings.windowrulev2 = [
    "nomaxsize, class:filen-desktop"
    # The progress window instantly closes as soon as it loses focus
    "stayfocused, class:filen-desktop"
  ];

  persistence.directories = [ ".config/filen-desktop" ];
}
