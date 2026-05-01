{ pkgs, config, ... }:

{
  imports = [ ./wayland-base.nix ];

  home.packages = with pkgs; [
    # :: sway itself is installed system-wide via programs.sway.enable
    swayidle
    swaybg

    # :: Lock screen (sway config locks via gtklock, not swaylock)
    gtklock

    # :: Referenced by sway/config binds and exec lines
    wlsunset        # :: night-light
    bemoji          # :: $mod+. emoji picker
    cliphist        # :: clipboard history
    pamixer         # :: volume binds
    wob             # :: volume/brightness overlay
    brightnessctl   # :: XF86MonBrightness binds
    jq              # :: per-window screenshot bind
    qalculate-gtk   # :: calc.sh popup
  ];

  # :: Symlink sway config from dotfiles (mirrors niri pattern)
  # :: This pulls in config, scripts/, and wallpapers/ in one shot
  xdg.configFile."sway".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/thanmatt-dotfiles/sway";

  # :: Symlink swaylock and gtklock configs
  xdg.configFile."swaylock".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/thanmatt-dotfiles/swaylock";

  xdg.configFile."gtklock".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/thanmatt-dotfiles/gtklock";

  # :: Login is handled by ly (configured in configuration.nix).
  # :: Pick the Sway session from ly's menu instead of auto-exec on TTY1.

  programs.fish.shellAliases = {
    Sway = "vi ~/.config/sway/config";
  };
}
