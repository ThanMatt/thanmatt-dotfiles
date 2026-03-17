{ ... }:

{
  imports = [
    ../../modules/base.nix
    ../../modules/de/i3.nix
  ];

  home.username = "dubi";
  home.homeDirectory = "/home/dubi";
  home.stateVersion = "24.11";
}
