{ pkgs, lib, config, ... }:

{
  # :: macOS home profile. Wraps the cross-platform core with macOS-only bits.
  # :: No Wayland/DE modules — window management on macOS is AeroSpace.
  imports = [ ./common.nix ];

  # :: AeroSpace tiling WM config — lives at ~/.aerospace.toml on macOS.
  home.file.".aerospace.toml".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/aerospace/.aerospace.toml";

  # :: macOS-only packages (add as needed). AeroSpace itself and most GUI apps
  # :: come from Homebrew rather than nixpkgs; here we only manage its config.
  home.packages = with pkgs; [
  ];
}
