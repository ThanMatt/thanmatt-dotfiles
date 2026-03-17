{ pkgs, config, ... }:

{
  # :: X11 / i3 — no wayland-base needed

  home.packages = with pkgs; [
    i3lock
    rofi
    picom
    feh          # :: wallpaper
    xss-lock
    dex          # :: XDG autostart
    xclip
    xdotool
    arandr       # :: display layout GUI
    pavucontrol
  ];

  xsession.windowManager.i3 = {
    enable = true;
    config = null;
    extraConfig = builtins.readFile
      "${config.home.homeDirectory}/thanmatt-dotfiles/i3/config";
  };

  # :: Symlink polybar config from dotfiles
  xdg.configFile."polybar".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/thanmatt-dotfiles/polybar";

  # :: Symlink picom config from dotfiles
  xdg.configFile."picom.conf".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/thanmatt-dotfiles/picom/picom.conf";

  programs.fish.shellAliases = {
    I3      = "vi ~/.config/i3/config";
    Polybar = "vi ~/.config/polybar/config.ini";
  };
}
