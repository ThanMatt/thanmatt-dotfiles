{ pkgs, config, ... }:

{
  imports = [ ./wayland-base.nix ];

  home.packages = with pkgs; [
    niri
    xwayland-satellite # :: X11 app support under Niri
  ];

  # :: Symlink niri config from dotfiles
  xdg.configFile."niri/config.kdl".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/thanmatt-dotfiles/niri/config.kdl";

  # :: Login is handled by ly (configured in configuration.nix).
  # :: Pick the Niri session from ly's menu instead of auto-exec on TTY1.

  programs.fish.shellAliases = {
    Niri = "vi ~/.config/niri/config.kdl";
  };
}
