{ pkgs, ... }:

{
  # :: Plasma 6 (KDE) — Wayland desktop environment
  # ::
  # :: Core enablement lives in configuration.nix:
  # ::   services.desktopManager.plasma6.enable = true;
  # ::
  # :: This module is the user-level (home-manager) side. Plasma manages most
  # :: of its own settings via GUI (System Settings), so this is intentionally
  # :: minimal — extend with plasma-manager later if you want declarative
  # :: configs for konsole, dolphin, kwin, etc.

  home.packages = with pkgs; [
    # :: Add user-level Plasma apps here as needed.
    # :: Most core apps (kate, dolphin, konsole, gwenview, okular) come bundled
    # :: with plasma6 at the system level.
  ];

  programs.fish.shellAliases = {
    Plasma = "systemsettings";
  };
}
