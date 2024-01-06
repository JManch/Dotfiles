{ config
, nixosConfig
, pkgs
, lib
, ...
}:
let
  hyprshot = "${pkgs.hyprshot}/bin/hyprshot";
  desktopCfg = config.modules.desktop;
  osDesktopEnabled = nixosConfig.usrEnv.desktop.enable;
  cfg = config.modules.desktop.hyprland;
  mod = cfg.modKey;
  modShift = "${cfg.modKey}SHIFT";
  modShiftCtrl = "${cfg.modKey}SHIFTCONTROL";
  getMonitorByNumber = number: lib.fetchers.getMonitorByNumber nixosConfig number;
  hyprctl = "${config.wayland.windowManager.hyprland.package}/bin/hyprctl";
  getOption = option: type: "${hyprctl} getoption ${option} -j | ${pkgs.jaq}/bin/jaq -r '.${type}'";
in
lib.mkIf (osDesktopEnabled && desktopCfg.windowManager == "hyprland")
{
  home.packages = [ pkgs.jaq ];

  wayland.windowManager.hyprland = {
    settings.bind =
      [
        # General
        "${modShift}, Q, exit,"
        "${modShift}, W, killactive,"
        "${mod}, C, togglefloating,"
        "${mod}, E, fullscreen, 1"
        "${modShift}, E, fullscreen, 0"
        "${mod}, Z, pin, active"

        # Movement
        "${mod}, H, movefocus, l"
        "${mod}, L, movefocus, r"
        "${mod}, K, movefocus, u"
        "${mod}, J, movefocus, d"
        "${modShift}, H, movewindow, l"
        "${modShift}, L, movewindow, r"
        "${modShift}, K, movewindow, u"
        "${modShift}, J, movewindow, d"
        "${mod}, mouse:276, workspace, r-1"
        "${mod}, mouse:275, workspace, r+1"
        "${mod}, mouse_up, workspace, r+1"
        "${mod}, mouse_down, workspace, r-1"
        "${mod}, Left, workspace, r-1"
        "${mod}, Right, workspace, r+1"

        # Monitors
        "${mod}, Comma, focusmonitor, ${(getMonitorByNumber 2).name}"
        "${mod}, Period, focusmonitor, ${(getMonitorByNumber 1).name}"
        "${modShift}, Comma, movecurrentworkspacetomonitor, ${(getMonitorByNumber 2).name}"
        "${modShift}, Period, movecurrentworkspacetomonitor, ${(getMonitorByNumber 1).name}"

        # Dwindle
        "${mod}, P, pseudo,"
        "${mod}, X, togglesplit,"
        "${mod}, M, exec, ${hyprctl} keyword dwindle:no_gaps_when_only $(($(${getOption "dwindle:no_gaps_when_only" "int"}) ^ 1))"

        # Hyprshot
        ", Print, exec, ${hyprshot} -m region --clipboard-only"
        "${mod}, Print, exec, ${hyprshot} -m region"
        "${modShift}, Print, exec, ${hyprshot} -m output"

        # Workspaces other
        "${mod}, N, workspace, previous"
        "${mod}, S, togglespecialworkspace,"
        "${modShift}, S, movetoworkspacesilent, special"
      ] ++ (
        # Workspaces
        let
          workspaceNumbers = lib.lists.map (w: builtins.toString w) (lib.lists.range 1 9);
          workspaceBinds = w: [
            "${mod}, ${w}, workspace, ${w}"
            "${modShift}, ${w}, movetoworkspace, ${w}"
            "${modShiftCtrl}, ${w}, movetoworkspacesilent, ${w}"
          ];
        in
        lib.lists.concatMap workspaceBinds workspaceNumbers
      );
    settings.bindm = [
      # Mouse window interaction
      "${mod}, mouse:272, movewindow"
      "${mod}, mouse:273, resizewindow"
    ];
    # Order-sensitive config has to go here
    extraConfig = ''
      bind = ${mod}, R, submap, resize
      submap = resize
      binde=, L, resizeactive, 20 0
      binde=, H, resizeactive, -20 0
      binde=, K, resizeactive, 0 -20
      binde=, J, resizeactive, 0 20
      bind= , Escape, submap, reset
      submap = reset
    '';
  };
}
