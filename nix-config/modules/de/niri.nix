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

  # :: Start Niri on TTY1 login (fish shell)
  programs.fish.interactiveShellInit = ''
    if status is-login
        if test -z "$DISPLAY"; and test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = 1
            exec niri-session
        end
    end
  '';

  programs.fish.shellAliases = {
    Niri = "vi ~/.config/niri/config.kdl";
  };
}
