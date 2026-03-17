{ pkgs, ... }:

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
