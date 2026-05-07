{ pkgs, lib, isVM ? false, isUEFI ? true, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/fonts.nix
    (if isUEFI then ../../modules/boot/uefi.nix else ../../modules/boot/bios.nix)
  ] ++ lib.optional isVM ../../modules/vm/virtualbox.nix;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Manila";

  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  # :: Window managers / desktop environments — system-level enablement.
  # :: Each adds a session entry that ly (the display manager) discovers.
  programs.niri.enable = true;
  programs.sway.enable = true;
  services.desktopManager.plasma6.enable = true;

  # :: ly — minimal TTY display manager / session switcher.
  # :: Pick niri / sway / plasma at login from the same place.
  services.displayManager.ly.enable = true;

  # :: Plasma + most Wayland apps expect PipeWire for audio.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };
  security.rtkit.enable = true;
  security.pam.services.gtklock = {};

  # :: keyd — kernel-level key remapping, works on Wayland and TTY.
  # :: Caps hold → nav layer (hjkl as arrows), tap → noop.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main.capslock = "overload(nav, noop)";
        nav = {
          h = "left";
          j = "down";
          k = "up";
          l = "right";
        };
      };
    };
  };

  virtualisation.docker.enable = true;

  users.users.dubi = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "docker" ];
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget

    # :: Build deps for asdf-python (compiles from source)
    gcc
    gnumake
    openssl
    zlib
    bzip2
    readline
    sqlite
    libffi
    xz
    ncurses
    pkg-config
  ];

  system.stateVersion = "24.11";
}
