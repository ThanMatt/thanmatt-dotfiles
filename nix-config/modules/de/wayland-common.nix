{ pkgs, ... }:

{
  # :: Shared Wayland essentials needed by any wlroots WM (sway/niri), independent
  # :: of which shell profile is in use (wayland-base = vanilla bar stack, or
  # :: wayland-noctalia = Noctalia). Both of those import this file.

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    LIBVA_DRIVER_NAME  = "iHD";
  };

  home.packages = with pkgs; [
    wl-clipboard
    rofi          # :: used by sway's cliphist-rofi-img script
    grim          # :: screenshots
    slurp         # :: region select for screenshots
    swappy        # :: screenshot annotation
  ];
}
