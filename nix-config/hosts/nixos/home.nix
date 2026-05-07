{ ... }:

{
  imports = [
    ../../modules/base.nix
    # ../../modules/de/niri.nix
    ../../modules/de/sway.nix
    ../../modules/de/plasma.nix
    # ../../modules/mobile.nix
  ];

  home.username = "dubi";
  home.homeDirectory = "/home/dubi";
  home.stateVersion = "24.11";
}
