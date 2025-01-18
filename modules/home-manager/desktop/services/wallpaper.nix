{
  lib,
  pkgs,
  config,
  desktopEnabled,
  ...
}@args:
let
  inherit (lib)
    ns
    mkIf
    mkMerge
    boolToString
    optional
    getExe
    ;
  inherit (config.${ns}.desktop.services) darkman;
  cfg = config.${ns}.desktop.services.wallpaper;
  wallpaperCache = "${config.xdg.cacheHome}/wallpaper";
  wallpapers =
    type: "${(lib.${ns}.flakePkgs args "nix-resources").wallpapers."${type}-wallpapers"}/wallpapers";

  setWallpaper = pkgs.writeShellApplication {
    name = "set-wallpaper";
    runtimeInputs = optional darkman.enable config.services.darkman.package;
    text = # bash
      ''
        randomise=${boolToString cfg.randomise.enable};
        darkman=${boolToString darkman.enable};
        darkman_hass=${boolToString (darkman.switchMethod == "hass")};
        random_wallpaper_cache="${wallpaperCache}/wallpaper"

        if [ "$darkman" = true ]; then
          theme=$(darkman get)
          # The darkman hass switch method may take some time to update
          # so need to wait
          if [ "$darkman_hass" = true ]; then
            attempt=0
            while [ "$theme" = "null" ]; do
              if (( attempt >= 10 )); then
                echo "Darkman hass did not update in time. Defaulting to dark theme"
                break
              fi
              echo "Waiting for darkman hass update..."
              sleep 0.5
              theme=$(darkman get)
              attempt=$((attempt + 1))
            done
          fi

          # If darkman is in manual mode the theme on boot will be null so
          # default to dark theme. Also covers hass timeout scenario.
          if [ "$theme" = "null" ]; then
            theme="dark"
          fi

          random_wallpaper_cache="${wallpaperCache}/$theme-wallpaper"
        fi

        if [ "$randomise" = true ]; then
          if [ ! -f "$random_wallpaper_cache" ]; then
            ${getExe randomiseWallpaper};
          fi
          wallpaper=$(<"$random_wallpaper_cache")

          # Cached wallpaper paths might be invalid after garbage collection
          if [ ! -f "$wallpaper" ]; then
            ${getExe randomiseWallpaper};
            wallpaper=$(<"$random_wallpaper_cache")
          fi
        elif [ "$darkman" = true ]; then
          if [ "$theme" = "dark" ]; then
            wallpaper="${cfg.defaults.dark}"
          else
            wallpaper="${cfg.defaults.light}"
          fi
        else
          wallpaper="${cfg.defaults.default}"
        fi

        ${cfg.setWallpaperCmd} "$wallpaper"
      '';
  };

  randomiseWallpaper = pkgs.writeShellApplication {
    name = "randomise-wallpaper";
    runtimeInputs =
      (with pkgs; [
        coreutils
        findutils
      ])
      ++ optional darkman.enable config.services.darkman.package;
    text = # bash
      ''
        function randomise_cache() {
          wallpapers="$1"
          cache_file="$2"
          previous_wallpaper=""
          [[ -f "$cache_file" ]] && previous_wallpaper=$(<"$cache_file")
          # Randomly select a wallpaper excluding the previous
          new_wallpaper=$(
            find "$wallpapers" -type f ! -name "$(basename "$previous_wallpaper")" -print0 |
            shuf -z -n 1 | tr -d '\0'
          )
          echo "$new_wallpaper" > "$cache_file"
        }

        darkman=${boolToString darkman.enable}
        if [ "$darkman" = true ]; then
          randomise_cache "${wallpapers "dark"}" "${wallpaperCache}/dark-wallpaper"
          randomise_cache "${wallpapers "light"}" "${wallpaperCache}/light-wallpaper"
        else
          randomise_cache "${wallpapers "all"}" "${wallpaperCache}/wallpaper"
        fi
      '';
  };
in
mkIf (cfg.setWallpaperCmd != null && desktopEnabled) (mkMerge [
  {
    systemd.user.services.set-wallpaper = {
      Unit = {
        Description = "Set the desktop wallpaper";
        X-SwitchMethod = "keep-old";
        Requisite = [ cfg.wallpaperUnit ];
        After =
          [ cfg.wallpaperUnit ]
          ++ optional cfg.randomise.enable "randomise-wallpaper.service"
          ++ optional darkman.enable "darkman.service";
      };

      Service = {
        Type = "oneshot";
        ExecStart = getExe setWallpaper;
      };

      Install.WantedBy = [ cfg.wallpaperUnit ];
    };
  }

  (mkIf cfg.randomise.enable {
    persistence.directories = [ ".cache/wallpaper" ];

    programs.zsh.shellAliases.randomise-wallpaper = "systemctl start --user randomise-wallpaper";

    darkman.switchScripts.wallpaper = _: ''
      systemctl start --user set-wallpaper
    '';

    systemd.user = {
      services.randomise-wallpaper = {
        Unit = {
          Description = "Randomise the desktop wallpaper";
          Before = [ "set-wallpaper.service" ];
          Wants = [ "set-wallpaper.service" ];
          X-SwitchMethod = "keep-old";
        };

        Service = {
          Type = "oneshot";
          ExecStart = [ (getExe randomiseWallpaper) ];
        };
      };

      timers.randomise-wallpaper = {
        Unit = {
          Description = "Timer for randomising the desktop wallpaper";
          X-SwitchMethod = "keep-old";
        };

        Timer = {
          OnCalendar = cfg.randomise.frequency;
          Persistent = true;
        };

        Install.WantedBy = [ "timers.target" ];
      };
    };
  })
])