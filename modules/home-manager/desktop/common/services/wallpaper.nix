{ lib
, pkgs
, config
, osConfig
, ...
} @ args:
let
  inherit (lib) mkIf mkMerge optional getExe getExe' utils optionalString;
  inherit (config.modules.desktop.services) darkman;
  cfg = config.modules.desktop.services.wallpaper;
  wallpapers = (utils.flakePkgs args "nix-resources").wallpapers;

  randomiseWallpaper = pkgs.writeShellApplication {
    name = "randomise-wallpaper";
    runtimeInputs = with pkgs; [ coreutils findutils ];
    text = /*bash*/ ''

      dir="${wallpapers.all-wallpapers}/wallpapers"
      ${optionalString darkman.enable /*bash*/ ''
        if [ "$(${getExe config.services.darkman.package} get)" = "light" ]; then
          dir="${wallpapers.light-wallpapers}"
        else
          dir="${wallpapers.dark-wallpapers}"
        fi
      ''}
      cache_file="${config.xdg.cacheHome}/wallpaper"
      previous_wallpaper=""
      [[ -f "$cache_file" ]] && previous_wallpaper=$(<"$cache_file")
      # Randomly select a wallpaper excluding the previous
      new_wallpaper=$(
        find "$dir" -type f ! -wholename "$previous_wallpaper" -print0 |
        shuf -z -n 1 | tr -d '\0'
      )
      echo "$new_wallpaper" > "$cache_file"

    '';
  };
in
mkIf (osConfig.usrEnv.desktop.enable && cfg.setWallpaperCmd != null) (mkMerge [
  {
    systemd.user.services.set-wallpaper = {
      Unit = {
        Description = "Set the desktop wallpaper";
        X-SwitchMethod = "keep-old";
        PartOf = [ "graphical-session.target" ];
        Requisite = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
        ] ++ optional cfg.randomise "randomise-wallpaper.service"
        ++ optional darkman.enable "darkman.service";
      };

      Service =
        let
          wallpaperToSet = if cfg.randomise then "\"$(<${config.xdg.cacheHome}/wallpaper)\"" else cfg.default;
          sh = getExe' pkgs.bash "sh";
        in
        {
          Type = "oneshot";
          ExecStartPre =
            # If this is a fresh install and the wallpaper cache does not exist,
            # randomise straight away. This is because daily / weekly timers
            # won't necessarily trigger on the very first boot

            # TODO: Minor issue but if full garbage collection is run and a
            # randomise is not triggered before the next boot the wallpaper path
            # inside the cache file will be invalidated and the wallpaper will
            # not be applied. Can maybe add a check that runs randomiseWallpaper
            # if the wallpaper file pointed to in the cache does not exist.
            lib.lists.optional cfg.randomise
              "${sh} -c '[[ -f \"${config.xdg.cacheHome}/wallpaper\" ]] || ${getExe randomiseWallpaper}'";
          ExecStart = "${sh} -c '${cfg.setWallpaperCmd} ${wallpaperToSet}'";
        };

      Install.WantedBy = optional (!(darkman.enable && cfg.randomise.enable)) "graphical-session.target";
    };
  }

  (mkIf cfg.randomise {
    persistence.files = [ ".cache/wallpaper" ];

    programs.zsh.shellAliases.randomise-wallpaper = "systemctl start --user randomise-wallpaper";

    darkman.switchScripts.wallpaper = theme: /*bash*/ ''
      systemctl start --user randomise-wallpaper
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

      timers.randomise-wallpaper = mkIf (!darkman.enable) {
        Unit = {
          Description = "Timer for randomising the desktop wallpaper";
          X-SwitchMethod = "keep-old";
        };

        Timer = {
          Unit = "randomise-wallpaper.service";
          OnCalendar = cfg.randomiseFrequency;
          Persistent = true;
        };

        Install.WantedBy = [ "timers.target" ];
      };
    };
  })
])
