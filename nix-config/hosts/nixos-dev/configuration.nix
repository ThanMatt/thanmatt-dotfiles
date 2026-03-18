{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/fonts.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-dev";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Manila";

  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  programs.niri.enable = true;

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
