{ pkgs, config, ... }:

{
  # :: "Vanilla" Wayland shell profile: waybar (bar) + mako (notifications) +
  # :: wofi (launcher) + wlogout (logout). This is the fallback if NOT using the
  # :: Noctalia shell — the alternative profile is ./wayland-noctalia.nix.
  # :: Shared Wayland essentials live in ./wayland-common.nix.
  imports = [ ./wayland-common.nix ];

  programs.waybar = {
    enable = true;
    systemd.enable = false; # :: niri config handles startup via spawn-at-startup
  };

  # :: Symlink the vanilla shell configs from dotfiles.
  xdg.configFile."waybar".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/waybar";
  xdg.configFile."wlogout".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/wlogout";
  xdg.configFile."wofi".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/wofi";
  xdg.configFile."mako".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/mako";

  home.packages = with pkgs; [
    mako       # :: notifications
    wlogout    # :: logout screen
    wofi       # :: app launcher
  ];
}
