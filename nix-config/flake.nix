{
  description = "Thanmatt NixOS Configuration Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
  let
    # :: Helper to reduce boilerplate per host.
    # :: Flags:
    # ::   isVM    — toggles VM-specific modules (e.g. VirtualBox guest additions)
    # ::   isUEFI  — picks bootloader: true=systemd-boot/UEFI, false=GRUB/BIOS
    mkSystem = { hostname, isVM ? false, isUEFI ? true, system ? "x86_64-linux" }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs isVM isUEFI; };
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          ./hosts/${hostname}/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.dubi = import ./hosts/${hostname}/home.nix;
          }
        ];
      };
  in
  {
    nixosConfigurations = {
      nixos-dev = mkSystem { hostname = "nixos-dev"; isVM = true; isUEFI = false; };
      nixos     = mkSystem { hostname = "nixos"; };
      x11-dev   = mkSystem { hostname = "x11-dev"; };
    };
  };
}
