{ lib
, pkgs
, config
, osConfig
, ...
}:
let
  inherit (lib) mkIf getExe';
  cfg = osConfig.modules.programs.gaming.steam;
in
mkIf cfg.enable
{
  # Fix slow steam client downloads https://redd.it/16e1l4h
  home.file.".steam/steam/steam_dev.cfg".text = ''
    @nClientDownloadEnableHTTP2PlatformLinux 0
  '';

  # WARN: Having third mirrored monitor enabled before launching seems to break
  # games (black screen in content manager). The issue doesn't occur if I
  # enable monitor 3 after content manager has already launched. I suspect it's
  # a hyprland bug but needs further investigation.

  # RDR2 Modded Launch Arguments:
  # WINEDLLOVERRIDES=EasyHook,EasyHook64,EasyLoad64,NativeInterop,version,dinput8,ScriptHookRDR2,ModManager.Core,ModManager.NativeInterop,NLog=n,b %command%

  # VR Launch Arguments:
  # PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc XRT_COMPOSITOR_SCALE_PERCENTAGE=140 XRT_COMPOSITOR_COMPUTE=1 SURVIVE_GLOBALSCENESOLVER=0 SURVIVE_TIMECODE_OFFSET_MS=-6.94 %command%

  # Assetto Corsa Setup:
  # - Run assetto corsa once then close
  # - Launch winecfg in protontricks and enable hidden files in wine file browser
  # - Inside the winecfg libraries tab add a new override for library 'dwrite'
  # - Run `protontricks 244210 corefonts` (can also be installed through UI but the pop-ups are annoying)
  # - Download content manager and place in steamapps/common/assettocorsa folder
  # - Rename content manager executable to 'Content Manager Safe.exe'
  # - Symlink loginusers.vdf to the prefix with `ln -s ~/.steam/root/config/loginusers.vdf ~/.local/share/Steam/steamapps/compatdata/244210/pfx/drive_c/Program\ Files\ \(x86\)/Steam/config/loginusers.vdf`
  # - Launch content manager with `protontricks-launch --appid 244210 ./Content\ Manager\ Safe.exe`
  # - Set assetto corsa root directory to z:/home/joshua/../steamapps/common/assettocorsa (using the z: drive is important)
  # - Inside Settings/Content Manager/Appearance settings disable window transparency and hardware acceleration for UI
  # - Inside Settings/Content Manager/Drive click the 'Switch game start to Steam' button
  #   it will show a warning about replacing the AssettoCorsa.exe, proceed
  # - Close the protontricks-launch instance of content manager and launch assetto corsa from Steam
  # - When installing custom shaders patch install one of the latest versions (old stable versions don't work)

  modules.programs.gaming = {
    gameClasses = [
      "steam_app.*"
      "cs2"
    ];

    tearingExcludedClasses = [
      "steam_app_1174180" # RDR2 - half-vsync without tearing is preferrable
      "steam_app_881100" # Noita - tearing lags cursor
    ];
  };

  desktop.hyprland.settings.windowrulev2 = [
    # Main steam window
    "workspace emptym silent, class:^(steam)$, title:^(Steam)$"

    # Steam sign-in window
    "noinitialfocus, class:^(steam)$, title:^(Sign in to Steam)$"
    "workspace special:loading silent, class:^(steam)$, title:^(Sign in to Steam)$"

    # Friends list
    "float, class:^(steam)$, title:^(Friends List)$"
    "size 360 700, class:^(steam)$, title:^(Friends List)$"
    "center, class:^(steam)$, title:^(Friends List)$"
  ];

  programs.zsh.shellAliases = {
    beam-mp = "${getExe' pkgs.protontricks "protontricks-launch"} --appid 284160 ${config.home.homeDirectory}/.local/share/Steam/steamapps/compatdata/284160/pfx/dosdevices/c:/users/steamuser/AppData/Roaming/BeamMP-Launcher/BeamMP-Launcher.exe";
  };
}
