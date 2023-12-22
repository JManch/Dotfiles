{ inputs, pkgs, ... }:
{
  imports = [
    ./home.nix
    ./shell
    ./programs/alacritty.nix
    ./programs/neovim
    ./programs/btop.nix
    ./programs/git.nix
    ./programs/firefox.nix
  ];
}
