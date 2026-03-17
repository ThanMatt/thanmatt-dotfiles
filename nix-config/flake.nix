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
    # :: Helper to reduce boilerplate per host
    mkSystem = { hostname, system ? "x86_64-linux" }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
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
      nixos-dev     = mkSystem { hostname = "nixos-dev"; };
      x11-dev = mkSystem { hostname = "x11-dev"; };
    };
  };
}
