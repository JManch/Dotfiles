{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf getExe mkForce mkDefault;
  inherit (config.modules.core) homeManager;
  inherit (config.device) gpu;
  cfg = config.modules.system.desktop;
  extensions = with pkgs.gnomeExtensions; [
    appindicator
    night-theme-switcher
    dash-to-dock
  ];
in
mkIf (cfg.enable && cfg.desktopEnvironment == "gnome")
{
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    # Suspend is temperamental on nvidia GPUs
    displayManager.gdm.autoSuspend = !(gpu.type == "nvidia");
    desktopManager.gnome.enable = true;
  };

  # Gnome uses network manager
  modules.system.networking.useNetworkd = mkForce false;

  # Only enable the power management feature on laptops
  services.upower.enable = mkForce (config.device.type == "laptop");
  services.power-profiles-daemon.enable = mkForce (config.device.type == "laptop");

  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    gnome.epiphany
  ];

  environment.systemPackages = extensions ++ [
    pkgs.gnome.gnome-tweaks
  ];

  hm = mkIf homeManager.enable {
    modules.desktop.terminal = {
      exePath = mkDefault (getExe pkgs.gnome-console);
      class = mkDefault "org.gnome.Consolez";
    };

    dconf.settings = {
      "org/gnome/desktop/peripherals/mouse" = {
        accel-profile = "flat";
      };

      "org/gnome/desktop/wm/preferences" = {
        action-middle-click-titlebar = "toggle-maximize-vertically";
        button-layout = "appmenu:minimize,maximize,close";
        # Focus follows mouse
        focus-mode = "sloppy";
        resize-with-right-button = true;
      };

      "org/gnome/mutter" = {
        edge-tiling = true;
      };

      "org/gnome/settings-daemon/plugins/color" = {
        night-light-enabled = true;
        night-light-schedule-automatic = true;
      };

      # Disable auto-suspend and power button suspend on nvidia
      "org/gnome/settings-daemon/plugins/power" = mkIf (gpu.type == "nvidia") {
        power-button-action = "interactive";
        sleep-inactive-ac-type = "nothing";
      };

      "org/gnome/shell" = {
        enabled-extensions = (map (e: e.extensionUuid) extensions) ++ [
          "drive-menu@gnome-shell-extensions.gcampax.github.com"
          "launch-new-instance@gnome-shell-extensions.gcampax.github.com"
        ];
      };

      "org/gnome/shell/extensions/nightthemeswitcher/commands" = {
        enabled = true;
        sunset = "gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Classic";
        sunrise = "gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Ice";
      };

      "org/gnome/shell/extensions/dash-to-dock" = {
        click-action = "focus-or-appspread";
        scroll-action = "cycle-windows";
        apply-custom-theme = true;
        show-trash = false;
      };

      "org/gnome/system/location" = {
        enabled = true;
      };
    };
  };
}