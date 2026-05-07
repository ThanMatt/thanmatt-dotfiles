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

  users.users.dubi = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
  ];

  system.stateVersion = "24.11";
}
