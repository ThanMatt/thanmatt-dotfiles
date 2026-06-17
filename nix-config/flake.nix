{
  description = "Thanmatt NixOS + standalone Home Manager Configuration Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
  let
    # :: NixOS system config — SYSTEM ONLY (boot, DEs, services, drivers).
    # :: Home Manager is no longer wired in here; the home side is applied
    # :: separately and identically on every platform via `home-manager switch`.
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
        ];
      };

    # :: Standalone Home Manager — OS-agnostic. The same modules drive Arch,
    # :: NixOS, and macOS; username/homeDirectory/stateVersion are injected here
    # :: so the modules never hardcode them. `hmTarget` lets the config refer to
    # :: its own flake attribute (e.g. the `update-all` alias).
    mkHome = { username, homeDirectory, system, modules, hmTarget }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        extraSpecialArgs = { inherit inputs hmTarget; };
        modules = modules ++ [{
          home = {
            inherit username homeDirectory;
            stateVersion = "24.11";
          };
        }];
      };
  in
  {
    nixosConfigurations = {
      nixos-dev = mkSystem { hostname = "nixos-dev"; isVM = true; isUEFI = false; };
      nixos     = mkSystem { hostname = "nixos"; };
      x11-dev   = mkSystem { hostname = "x11-dev"; };
    };

    homeConfigurations = {
      # :: Arch (this machine).
      "thanmatt@arch" = mkHome {
        username = "thanmatt";
        homeDirectory = "/home/thanmatt";
        system = "x86_64-linux";
        modules = [ ./home/linux.nix ];
        hmTarget = "thanmatt@arch";
      };

      # :: NixOS box.
      "dubi@nixos" = mkHome {
        username = "dubi";
        homeDirectory = "/home/dubi";
        system = "x86_64-linux";
        modules = [ ./home/linux.nix ];
        hmTarget = "dubi@nixos";
      };

      # :: macOS (Apple Silicon). Replace MACUSER with the real account name.
      "MACUSER@mac" = mkHome {
        username = "MACUSER";
        homeDirectory = "/Users/MACUSER";
        system = "aarch64-darwin";
        modules = [ ./home/darwin.nix ];
        hmTarget = "MACUSER@mac";
      };
    };
  };
}
