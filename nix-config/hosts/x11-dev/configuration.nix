{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # :: adjust to your disk

  networking.hostName = "x11-dev";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Manila";

  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  services.xserver = {
    enable = true;
    windowManager.i3.enable = true;
    displayManager.lightdm.enable = true;
  };

  users.users.dubi = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
  ];

  system.stateVersion = "24.11";
}
