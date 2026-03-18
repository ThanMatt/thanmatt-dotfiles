{ pkgs, config, ... }:

{
  # :: Shared Wayland dependencies — imported by niri.nix and sway.nix

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    LIBVA_DRIVER_NAME  = "iHD";
  };

  programs.waybar = {
    enable = true;
    systemd.enable = false; # :: niri config handles startup via spawn-at-startup
  };

  # :: Symlink waybar config from dotfiles
  xdg.configFile."waybar".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/waybar";

  # :: Symlink wlogout config from dotfiles
  xdg.configFile."wlogout".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/wlogout";
  #
  # :: Symlink wofi config from dotfiles
  xdg.configFile."wofi".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/wofi";

  # :: Symlink mako config from dotfiles
  xdg.configFile."mako".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/mako";

  home.packages = with pkgs; [
    mako       # :: notifications
    wlogout    # :: logout screen
    wofi       # :: app launcher
    rofi
    grim       # :: screenshots
    slurp      # :: region select for screenshots
    swappy     # :: screenshot annotation
    wl-clipboard
  ];
}
