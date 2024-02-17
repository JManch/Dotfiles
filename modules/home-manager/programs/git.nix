{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.modules.programs.git;
in
lib.mkIf cfg.enable {
  programs.git = {
    enable = true;
    userEmail = "JManch@protonmail.com";
    userName = "Joshua Manchester";
    extraConfig = {
      init.defaultBranch = "main";
      gpg.format = "ssh";
    };
    signing = {
      key = "${config.home.homeDirectory}/.ssh/id_ed25519";
      signByDefault = true;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      git.overrideGpg = true;
    };
  };

  programs.zsh = {
    shellAliases = {
      lg = "lazygit";
    };
    initExtra = ''
      lazygit() {
        ssh-add-quiet
        command ${config.programs.lazygit.package}/bin/lazygit "$@"
      }
    '';
  };

  persistence.files = [
    ".config/lazygit/state.yml"
  ];
}
