{ pkgs, config, ... }:

{
  # :: "Noctalia" Wayland shell profile: the Noctalia desktop shell (Quickshell/QML)
  # :: provides the bar, notifications, and launcher — replacing waybar/mako/wofi.
  # :: The alternative profile is ./wayland-base.nix (vanilla). Shared Wayland
  # :: essentials live in ./wayland-common.nix.
  imports = [ ./wayland-common.nix ];

  # :: Noctalia user settings (JSON — no native HM module) symlinked from the repo,
  # :: same pattern as nvim/doom. Read by noctalia at ~/.config/noctalia.
  xdg.configFile."noctalia".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/thanmatt-dotfiles/noctalia";

  # :: Noctalia runtime. The (shared) sway config launches it the Arch way —
  # ::   exec qs -c noctalia-shell
  # :: so NixOS needs: (a) `qs` on PATH, provided by noctalia-qs (noctalia's own
  # :: quickshell fork), and (b) the bundled shell QML discoverable as the
  # :: quickshell config named "noctalia-shell" (see below). `noctalia-shell` (the
  # :: wrapper) is kept too as a direct launcher + to put its assets on XDG_DATA_DIRS.
  home.packages = with pkgs; [
    noctalia-shell
    noctalia-qs
  ];

  # :: Expose the bundled QML as `qs -c noctalia-shell` (mirrors Arch's layout), so
  # :: the shared sway config — autostart AND every `ipc call …` keybind — resolves
  # :: identically on Arch and NixOS with zero per-platform edits.
  # :: recursive = true is REQUIRED: quickshell only accepts a config when the
  # :: `<name>` entry is a real directory, not a symlinked-dir, so HM must
  # :: materialise the dir and symlink the files inside it individually.
  xdg.configFile."quickshell/noctalia-shell" = {
    source = "${pkgs.noctalia-shell}/share/noctalia-shell";
    recursive = true;
  };
}
