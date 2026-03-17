{ pkgs, config, ... }:

{
  imports = [ ./wayland-base.nix ];

  home.packages = with pkgs; [
    swaylock
    swayidle
    swaybg
  ];

  wayland.windowManager.sway = {
    enable = true;
    # :: Let your dotfiles config.kdl drive the config
    config = null;
    extraConfig = builtins.readFile
      "${config.home.homeDirectory}/thanmatt-dotfiles/sway/config";
  };

  # :: Start Sway on TTY1 login (fish shell)
  programs.fish.interactiveShellInit = ''
    if status is-login
        if test -z "$DISPLAY"; and test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = 1
            exec sway
        end
    end
  '';

  programs.fish.shellAliases = {
    Sway = "vi ~/.config/sway/config";
  };
}
