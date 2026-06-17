{ pkgs, lib, config, ... }:

{
  # :: Linux home profile (Arch + NixOS). Wraps the cross-platform core with
  # :: Wayland DE configs and Linux-only packages/env. On NixOS the DEs are
  # :: ENABLED at the system level (configuration.nix); on Arch they come from
  # :: pacman — either way these modules just supply the user-level configs.
  imports = [
    ./common.nix
    ../modules/de/sway.nix
    ../modules/de/plasma.nix
  ];

  home.sessionVariables = {
    GTK_IM_MODULE = "xim";
    MONITOR = "DP-0";
    ANDROID_HOME = "$HOME/Android/Sdk";
  };

  home.sessionPath = [
    "$HOME/develop/flutter/bin"
    "$HOME/Android/Sdk/cmdline-tools/latest/bin"
    "$HOME/Android/Sdk/platform-tools"
  ];

  home.packages = with pkgs; [
    firefox
    chromium
    proton-vpn-cli
  ];

  # :: Linux/machine-specific shell aliases (tools that only exist on Linux).
  programs.fish.shellAliases = {
    I3       = "vi ~/.config/i3/config";
    Polybar  = "vi ~/.config/polybar/config.ini";

    wd               = "waydroid";
    wdstart          = "waydroid show-full-ui";
    "wdstart-detach" = "waydroid show-full-ui &> /dev/null & disown";
    wdstop           = "waydroid session stop";
    wdrestart        = "waydroid session stop && waydroid show-full-ui";
    wdstatus         = "waydroid status";
    wdshell          = "waydroid shell";
    wdconnect        = "adb connect 192.168.240.112";
    wddevices        = "adb devices";
    wdphone          = "waydroid session stop && waydroid prop set persist.waydroid.width 506 && waydroid prop set persist.waydroid.height 2400 && waydroid show-full-ui";
    wdclean          = "waydroid session stop && sudo systemctl stop waydroid-container && sudo rm -rf /var/lib/waydroid /home/.waydroid ~/waydroid ~/.share/waydroid ~/.local/share/waydroid";

    vpn-killswitch  = "sudo ~/.local/bin/vpn-killswitch.sh";
    test-killswitch = "~/.local/bin/test-killswitch";

    # :: NixOS system rebuild (no-op on Arch — kept here for the NixOS box).
    system-update = "sudo nixos-rebuild switch --flake ~/thanmatt-dotfiles/nix-config#nixos";
  };

  # :: Optional, machine-local integrations — guarded so they're harmless when absent.
  programs.fish.interactiveShellInit = ''
    if test -f "$HOME/google-cloud-sdk/path.fish.inc"
        source "$HOME/google-cloud-sdk/path.fish.inc"
    end
    test -s "$HOME/.nvm-fish/nvm.fish"; and source "$HOME/.nvm-fish/nvm.fish"
  '';
}
