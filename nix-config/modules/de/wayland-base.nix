{ pkgs, config, ... }:

{
  # :: Shared Wayland dependencies — imported by niri.nix and sway.nix

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    LIBVA_DRIVER_NAME  = "iHD";
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;
  };

  # :: Symlink waybar config from dotfiles
  xdg.configFile."waybar".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/waybar";

  # :: Symlink wlogout config from dotfiles
  xdg.configFile."wlogout".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/wlogout";

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
